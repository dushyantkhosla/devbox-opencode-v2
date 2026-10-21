# opencode-devbox

Isolated Docker devbox for running OpenCode v2 on a remote Linux server.
The agent works in `/workspace` (a bind mount of the project on the host)
as non-root `dev` with passwordless sudo, inside tmux/zsh. Replaces
`dev-container`, `sandbox-opencode`, and `sandbox-opencode-v2-server`.

## What's included

- OpenCode v2 (fetched at build time, started manually), Node 22.23.3, pnpm 12.11.2, `uv`/`uvx` 0.13.1, CPython 3.14.8 (baked into `/opt/python`), Git, tmux, zsh (oh-my-zsh/Agnoster).
- Playwright CLI + pinned Chromium and WebKit (`PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright`, 1gb `/dev/shm`) and the PostgreSQL 18 client (`psql`, `pg_isready`, `pg_dump`/`pg_restore`) matching the host PG18 server.
- No compiler toolchain baked in; the agent `apt-get install`s `build-essential` via sudo when needed (lost on recreate).
- `dev` user with passwordless sudo (container only); GitHub HTTPS auth via `GITHUB_PAT` + askpass helper.
- Named volumes for OpenCode state, seeded config, and skills; joins the shared `devbox-net` network (postgres/mailpit from the host `compose.yml`). No database of its own.

## Requirements

Docker + Compose plugin on the server, and these exports in the shell that runs Compose:

```zsh
export GITHUB_PAT="..." GIT_USER_NAME="..." GIT_USER_EMAIL="..."
# Optional: HOST_WORKSPACE (default: dir holding the compose file), HOST_UID/HOST_GID (default 1000),
# OPENCODE_PORT (default 4096), OPENCODE_SERVER_PASSWORD, OPENAI_API_KEY, OPENROUTER_API_KEY, OPENCODE_API_KEY, TYPESAFE_API_KEY
```

Missing required values fail fast. Keep secrets in the shell environment, never in the repo.

## Quick start

Recommended layout — copy the compose file, `.devbox/`, and `.config/` into the project root:

```
project/
├── devbox.compose.yml
├── .devbox/
└── .config/opencode/    # seed config: opencode.json, agents/, commands/, plugins/, skills/
```

```sh
cd ~/code/my-project
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose -f devbox.compose.yml up --build -d
docker compose -f devbox.compose.yml exec opencode-devbox tmux new-session -A -s dev
# inside tmux, when the web UI is needed:
opencode serve --hostname 0.0.0.0 --port "$OPENCODE_PORT"
```

Central checkout instead: set `HOST_WORKSPACE` to the project dir; the command is the same.
Open `http://<server-ip>:4096` once `serve` runs. If `OPENCODE_SERVER_PASSWORD` is set, Basic auth (`opencode` / password) is required.

Per-project overrides go in a gitignored `.env` next to the compose file (`HOST_UID`, `HOST_GID`, `OPENCODE_PORT`, git identity). Use a distinct port per simultaneous project.

## Laptop client

Start `serve` in tmux first, then from the laptop:

```sh
docker run -it --rm \
  -v "$HOME/.config/opencode-v2/cli.json:/root/.config/opencode/cli.json:ro" \
  -e OPENCODE_SERVER_PASSWORD='...' \
  ghcr.io/anomalyco/opencode:2.0.29 --server "http://<server-ip>:<port>"
```

## Notes

- **Workspace:** `/workspace` is a bind mount; it survives `down -v`. Use a fine-grained PAT — it is visible inside the container.
- **Config seeding:** first start copies `.config/opencode/` from this checkout (`opencode.json`, `agents/`, `commands/`, `plugins/`, plus `skills/` into `~/.agents/skills`) into volumes; afterwards both sides are independent. Re-seed with:
  ```sh
  docker compose -f devbox.compose.yml exec opencode-devbox sh -c \
    'rm -f ~/.config/opencode/.host-config-seeded ~/.agents/skills/.host-skills-seeded'
  docker compose -f devbox.compose.yml restart opencode-devbox
  ```
- **Database/mail:** this file runs no postgres of its own; it joins the shared `devbox-net` network, so `postgres` (or `db`) and `mailpit` from the host `compose.yml` are reachable from inside the container.
- **Sudo files:** files the agent creates with sudo in `/workspace` end up owned by host-root; fix on the host with `sudo chown -R $(id -u):$(id -g) .`.
- **Volumes:** `opencode-data` (`~/.local`), `opencode-config` (`~/.config/opencode`), `agent-skills` (`~/.agents/skills`). `down` keeps them, `down -v` deletes them (never the workspace).
- **Security:** passwordless sudo, API keys, and `GITHUB_PAT` are visible inside the container; seed mounts are read-only; no Docker socket is mounted. Filesystem boundary, not a full devbox.
- **Update OpenCode:** `docker compose -f devbox.compose.yml build --no-cache opencode-devbox && docker compose -f devbox.compose.yml up -d --force-recreate opencode-devbox`

## Files

- `devbox.compose.yml` — workspace bind, seed mount (`./.config/opencode` → `/seed`), volumes, ports, shared `devbox-net` network.
- `.devbox/Dockerfile` — image (OpenCode fetch, Node/pnpm, uv + CPython 3.14.8, Playwright/Chromium + WebKit, PG18 client, `dev` user, dotfiles).
- `.devbox/entrypoint.sh` — seeds `/seed` into config/skills volumes on first start, sets git identity, then execs CMD (idle `sleep infinity`); the server is started manually.
- `.config/opencode/` — seed content: `opencode.json`, `agents/`, `commands/`, `plugins/`, `skills/`.
- `.devbox/AGENTS.md` — image manifest (baked toolchain, version pins, rebuild).
- `.devbox/.zshrc`, `.devbox/.tmux.conf`, `.devbox/.dockerignore`
