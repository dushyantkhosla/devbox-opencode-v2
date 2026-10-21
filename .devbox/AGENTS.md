# .devbox — dev container image manifest

This directory builds the devbox image (`devbox.compose.yml`). What is
baked in below is available in **every** session; do not `apt-get install`
anything on this list, and never install *services* (postgres, mailpit,
servers) — those run on the host via `compose.yml` (see root `AGENTS.md`
"Dev topology").

## Baked toolchain

- Node 22.23.3, `pnpm@12.11.2` (global), `uv` 0.13.1 / `uvx` in `/bin`,
  CPython 3.14.8 in `/opt/python`, `opencode` in `/usr/local/bin`, `tmux`,
  `zsh` + oh-my-zsh, `git` (HTTPS askpass helper).
- System utils: `ca-certificates curl fd-find git jq less nano procps ripgrep
  sudo tmux unzip zsh`, plus the **PostgreSQL 18 client** (`psql`, `pg_isready`,
  `pg_dump`/`pg_restore`) from the PGDG repo — matching the PG18 dev server;
  use it for grant SQL, readiness checks, and backups.
- **Playwright**: `@playwright/cli@0.1.22` + `playwright@1.64.0-alpha-1790635538000`
  (global) — the exact version the CLI pins, because a newer `playwright` ships
  a different browser revision and `playwright-cli` then refuses to launch.
  Browsers: `chromium-1247` / `chromium_headless_shell-1247` (Chrome for
  Testing 155.0.8059.12). Invoke as `playwright-cli open --browser=chromium
  <url>` — bare `open` fails (no branded Chrome here).
  `PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright` and `PWTEST_SOCKETS_DIR=/tmp/pw`
  are set image-wide; leave them alone — but `/tmp/pw` must stay writable by
  `dev` (it is chowned to the dev user at build time).
- Single user `dev` (UID/GID mapped to host via build args) with passwordless
  sudo. Missing *dev libraries* may be `apt-get install`ed on demand, but
  that is lost on rebuild — if you need it twice, add it to `Dockerfile`.

## Version pinning

Every tool the workflow depends on is pinned in `Dockerfile`: node, uv, pnpm,
the PostgreSQL client, the Playwright CLI **and** its browser build, and
CPython. Bump them deliberately and together (Playwright CLI ↔ `playwright` ↔
browser revision are a matched set). Still floating, on purpose:

- `opencode` — the v2 install script tracks latest (rebuild to update).
- `oh-my-zsh` — its installer tracks `master`.
- Debian apt patch versions of the generic utils (`curl`, `git`, …); only
  versions that matter behaviourally (e.g. `postgresql-client-18`) are exact.

## Deliberately NOT in the image

- No Docker CLI (`docker compose` runs on the host).
- No databases, mail servers, or app servers (host `compose.yml`).
- No `build-essential` (~400 MB; install on demand if a build needs it).

## Persistence

- `/workspace` is a bind mount (survives rebuilds). Persisted volumes:
  `/home/dev/.local`, `/home/dev/.config/opencode`, `/home/dev/.agents/skills`.
- Everything else (including `~/.cache` and manual `apt-get installs`) is
  ephemeral — hence browsers live in `/opt/ms-playwright`, not a home dir.

## Rebuild (host shell)

```bash
docker compose -f devbox.compose.yml build
docker compose -f devbox.compose.yml up -d --force-recreate
```

After editing `Dockerfile`, also update the list above.
