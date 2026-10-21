#!/bin/sh
# Seeds the checkout's config (bound read-only at /seed by devbox.compose.yml)
# into writable volumes on first start only — afterwards the container copies
# are independent: container edits never flow back to the checkout, checkout
# edits don't flow in (delete the marker to re-seed). Then sets git identity
# and idles. The OpenCode server is started manually from a tmux shell (see
# README).
set -eu

config="$HOME/.config/opencode"
if [ ! -e "$config/.host-config-seeded" ]; then
    cp /seed/opencode.json "$config/"
    cp -R /seed/agents /seed/commands /seed/plugins "$config/"
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

exec "$@"
