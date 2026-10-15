#!/bin/sh
# Seeds host files (config, agents, commands, skills) into writable volumes
# on first start only — afterwards the container copies are independent:
# container edits never flow back to the host, host edits don't flow in
# (delete the marker to re-seed). Then sets git identity and idles. The
# OpenCode server is started manually from a tmux shell (see README).
set -eu

config="$HOME/.config/opencode"
if [ ! -e "$config/.host-config-seeded" ]; then
    cp /seed/opencode.json "$config/"
    cp -R /seed/agents /seed/commands "$config/"
    chmod -R u+rwX "$config"
    touch "$config/.host-config-seeded"
fi

skills="$HOME/.agents/skills"
if [ ! -e "$skills/.host-skills-seeded" ]; then
    cp -R /seed/skills/. "$skills/"
    chmod -R u+rwX "$skills"
    touch "$skills/.host-skills-seeded"
fi

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

# Ensure managed Python 3.14 is available. `uv python install --default`
# installs `python3.14`, `python3`, and `python` into ~/.local/bin (already
# on PATH in the image); the interpreter lives in ~/.local/share/uv (the
# opencode-data volume), so it persists across restarts. Tolerate failure
# (offline first start) so the container still idles instead of crashing.
if ! uv python find 3.14 >/dev/null 2>&1; then
    echo "Installing Python 3.14 via uv..." >&2
    uv python install 3.14 --default \
        || echo "Warning: Python 3.14 install failed (no network?). Continuing without it." >&2
fi

exec "$@"
