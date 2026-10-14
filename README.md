# opencode-sandbox

OpenCode v2 sandbox for a remote Linux server: an isolated Docker environment
where the agent works on a project that lives on the server host, with a full
dev toolchain, passwordless sudo, and a persistent tmux shell. Replaces
`dev-container`, `sandbox-opencode`, and `sandbox-opencode-v2-server`.
Connect from your laptop with the existing `sandbox-opencode-v2-client`.

## What's included

- OpenCode v2, installed with the official installer at image-build time; the server is started manually when needed.
- Node.js 22 on Debian Bookworm slim, pnpm, `uv`/`uvx` (Python), Git.
- No compiler toolchain baked in (saves ~400 MB); the agent installs `build-essential` via sudo when a native build needs it (e.g. node-gyp without a prebuilt binary). The install doesn't survive a container recreate.
- Zsh (oh-my-zsh, Agnoster prompt, `.sandbox/.zshrc`), tmux (`.sandbox/.tmux.conf`, default-shell zsh).
- Non-root `dev` user with **passwordless sudo**, so the agent can install dependencies and start/stop services inside the sandbox.
- Persistent named volumes for OpenCode state and (seeded) config; the project itself is a bind mount.
- GitHub HTTPS authentication via a host-provided PAT and an askpass helper.
- Optional PostgreSQL behind a Compose profile.

Playwright and browser dependencies are intentionally not included; install them per project.

## Requirements

- Docker and the Docker Compose plugin on the server.
- Required exports in the shell that runs Compose (see below).

## Server environment

Export in `~/.zshrc` (or the shell startup file of the shell running Compose):

```zsh
export GITHUB_PAT="your-fine-grained-github-token"
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your-github-noreply-address"
export HOST_HOME="/home/your-user"        # home of the server user (not $HOME; Snap Docker can differ)

# Optional
export HOST_WORKSPACE="$HOST_HOME/code/my-project"  # override the bind source (default: the dir holding compose.yml)
export OPENCODE_PORT="4096"               # default 4096
export OPENCODE_SERVER_PASSWORD="..."     # if unset, the served port is unsecured
export OPENAI_API_KEY="..."               # optional provider keys
export OPENROUTER_API_KEY="..."
export OPENCODE_API_KEY="..."
export TYPESAFE_API_KEY="..."
export DATABASE_URL="postgresql://app:dev@postgres:5432/app"
```

Compose reads exported variables from its launching process; it does not read `~/.zshrc` itself. Required values fail fast when missing.

## Per-project layout (recommended)

Drop the sandbox into the project directory on the server: only `compose.yml` touches the project root; everything else lives in `.sandbox/`:

```
project/
├── compose.yml
└── .sandbox/
    ├── Dockerfile
    ├── .dockerignore
    ├── entrypoint.sh
    ├── .zshrc
    └── .tmux.conf
```

No `HOST_WORKSPACE` is needed — the project is bound from `.` — and the Compose project name derives from the directory name, so simultaneous projects only need distinct ports.

Adding another service later is straightforward: each service declares its own build context and Dockerfile, so containers built from different images coexist in one compose file:

```yaml
  another-service:
    build:
      context: ./other-dir   # that dir contains its own Dockerfile
      dockerfile: Dockerfile
```

Put the non-secret, host-specific values in a per-project `.env` next to `compose.yml` (Compose reads it automatically):

```dotenv
# .env — adjust per server user and project
HOST_UID=1000          # run: id -u
HOST_GID=1000          # run: id -g
HOST_HOME=/home/your-user
OPENCODE_PORT=4096     # unique per simultaneous project
GIT_USER_NAME=Your Name
GIT_USER_EMAIL=your-github-noreply-address
```

Keep secrets (`GITHUB_PAT`, provider API keys, `OPENCODE_SERVER_PASSWORD`) out of the repo: either export them in the server shell or put them in a gitignored `.env`. Committing the sandbox files themselves is fine — they contain no secrets; a gitignored `.env` keeps teammate checkouts clean.

Workflow:

```sh
cd ~/code/my-project          # contains the sandbox files
docker compose build          # HOST_UID/HOST_GID come from .env
docker compose up -d
docker compose exec opencode-sandbox tmux new-session -A -s dev
# inside tmux, when the web UI is needed:
opencode serve --hostname 0.0.0.0 --port "$OPENCODE_PORT"
```

## Quick start (central layout)

```sh
# 1. Put the project on the server at $HOST_WORKSPACE (clone it there or copy it).

# 2. Build (UID/GID args map the in-container dev user to the server user)
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build

# 3. Start the sandbox (it idles; nothing listens yet)
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up -d

# 4. Persistent development shell
docker compose exec opencode-sandbox tmux new-session -A -s dev
```

Inside tmux, when the web UI is needed:

```sh
opencode serve --hostname 0.0.0.0 --port "$OPENCODE_PORT"
```

Open `http://localhost:4096` on the server host, or `http://<host-lan-ip>:4096` from another device. Nothing answers until `serve` is running. If `OPENCODE_SERVER_PASSWORD` is set, HTTP Basic auth is required (username `opencode`); if unset, anyone who can reach the port has full access.

## Connect from your laptop (client)

Start `serve` inside tmux first (see above), then connect from your laptop with the client image:

```sh
docker run -it --rm \
  -v "$HOME/.config/opencode-v2/cli.json:/root/.config/opencode/cli.json:ro" \
  -e OPENCODE_SERVER_PASSWORD='XXXXXX' \
  ghcr.io/anomalyco/opencode:2.0.29 --server "http://XX.XX.XX.XX:XX"
```

Replace `XXXXXX` with the same `OPENCODE_SERVER_PASSWORD` the server was started with, and `http://XX.XX.XX.XX:XX` with `http://<server-ip>:<OPENCODE_PORT>` (e.g. `http://192.168.1.10:4096`).

## Git and the workspace

`/workspace` is a bind mount of the project on the server host — the bind source is the directory holding `compose.yml` (drop-in mode) or `HOST_WORKSPACE` (central layout). The repo survives `docker compose down -v`. Git runs inside the container with HTTPS remotes; the askpass helper supplies `x-access-token`/`$GITHUB_PAT` and stores no credential file. `GIT_USER_NAME`/`GIT_USER_EMAIL` are commit identity, set at startup.

Use a fine-grained PAT scoped to the needed repository. The PAT is visible to processes inside the container, including the agent.

## Config seeding

On first start the entrypoint copies host files into writable volumes and marks each seeded:

- `~/.config/opencode-v2/opencode.json`, `agents/`, `commands/` → `opencode-config` volume
- `~/.agents/skills` → `agent-skills` volume

Afterwards the in-container copies are **independent**: changes inside the container never flow back to the host, and host changes don't flow in either. Re-seed from the host after changing host files:

```sh
docker compose exec opencode-sandbox sh -c \
  'rm -f ~/.config/opencode/.host-config-seeded ~/.agents/skills/.host-skills-seeded'
docker compose restart opencode-sandbox
```

## Optional PostgreSQL

Not started by default:

```sh
docker compose --profile postgres up -d
```

Reachable as `postgres:5432` on the Compose network (not published to the host); default `postgresql://app:dev@postgres:5432/app`, overridable via `DATABASE_URL`.

## Multiple environments

Project names isolate containers, networks, and volumes; choose a distinct port per instance (no fixed container name):

```sh
HOST_HOME=... HOST_WORKSPACE=... OPENCODE_PORT=4096 docker compose -p project-a up -d --build
HOST_HOME=... HOST_WORKSPACE=... OPENCODE_PORT=4097 docker compose -p project-b up -d --build
```

## Sudo gotcha

The container's `dev` user has passwordless sudo **inside the container only** — it is not root on the host. If the agent uses sudo for an edit in `/workspace`, the file is created as container-root; on the bind mount it will then be owned by host-root. Fix afterwards with:

```sh
sudo chown -R $(id -u):$(id -g) /workspace
```

## Volumes and cleanup

| Mount                  | Contents                                  |
| ---------------------- | ----------------------------------------- |
| bind source (`.` or `$HOST_WORKSPACE`) | Project source (on the host — never deleted by Compose) |
| `opencode-data`        | OpenCode state under `/home/dev/.local`   |
| `opencode-config`      | Seeded OpenCode config                    |
| `postgres-data`        | PostgreSQL data (profile)                 |

```sh
docker compose down        # keeps volumes
docker compose down -v     # also deletes state/config/database (not the workspace)
```

## Security notes

- Passwordless sudo is scoped to the container; no Docker socket, SSH directory, or full host home is mounted.
- Host config/skills mounts are read-only; the agent can read them, so keep secrets out of them.
- API keys and `GITHUB_PAT` are passed through the environment and readable inside the container.
- This is a useful filesystem boundary, not a complete security sandbox.

## Updating OpenCode

The installer tracks `latest` at build time; rebuild without cache:

```sh
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build --no-cache opencode-sandbox
docker compose up -d --force-recreate opencode-sandbox
```

## Files

- `compose.yml` — bind-mounted workspace, volumes, ports, optional PostgreSQL; the only file that lives in the project root. Builds the image as `opencode-sandbox:latest`.
- `.sandbox/Dockerfile` — multi-stage image (opencode fetch, uv, final), UID-parameterized user with sudo.
- `.sandbox/entrypoint.sh` — seeds host config, sets git identity, then runs the idle command.
- `.sandbox/.zshrc`, `.sandbox/.tmux.conf` — shell/tmux setup, baked in.
- `SPEC.md` — design decisions behind this build.
