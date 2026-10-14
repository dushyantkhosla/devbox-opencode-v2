# syntax=docker/dockerfile:1
# Sandbox image for OpenCode v2 on a remote server: full dev toolchain
# (Node 22, pnpm, uv), non-root `dev` user with passwordless sudo, tmux/zsh.
# Built from source; rebuild to update OpenCode (installer tracks latest).
ARG NODE_VERSION=22

# --- Stage 1: fetch the opencode binary.
# curl/tar live only here, never in the final image. Same base as final,
# so layers are shared and nothing extra is pulled.
FROM node:${NODE_VERSION}-bookworm-slim AS opencode-installer
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL https://opencode.ai/v2/install | bash

# --- Stage 2: uv binary (official image; nothing else is taken from it) ---
FROM ghcr.io/astral-sh/uv:latest AS uv

# --- Stage 3: final sandbox image ---
FROM node:${NODE_VERSION}-bookworm-slim

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
# ARG (not ENV): noninteractive apt during build, nothing leaked into the image.
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SHELL=/bin/zsh \
    PNPM_HOME=/usr/local/share/pnpm \
    PATH="/usr/local/share/pnpm:/home/${USERNAME}/.local/bin:${PATH}"

COPY --from=uv /uv /uvx /bin/
COPY --from=opencode-installer /root/.opencode/bin/opencode /usr/local/bin/opencode

# One layer: system utils + pnpm. Apt lists and the npm cache are
# purged in the same RUN so they never persist in a layer.
#
# Trimmed set: bash/vim (not used — zsh + nano), locales (C.UTF-8 is built
# into Debian), openssh-client/gnupg (HTTPS-only remotes, no signed commits),
# fzf/iputils-ping/zip (install on demand if needed).
#
# build-essential (gcc/g++/make, ~350-400 MB) is deliberately NOT baked in:
# dependency installs rarely need native compilation, and the agent has
# passwordless sudo to `apt-get install build-essential` on demand when one
# does (e.g. node-gyp without a prebuilt binary). The manual install is lost
# on container recreate — acceptable.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      fd-find \
      git \
      jq \
      less \
      nano \
      procps \
      ripgrep \
      sudo \
      tmux \
      unzip \
      zsh \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g pnpm@latest \
    && npm cache clean --force \
    && chmod +x /usr/local/bin/opencode

# Git askpass helper for GitHub HTTPS: supplies x-access-token / GITHUB_PAT
# so interactive prompts are never needed and no credential file is written.
RUN printf '%s\n' \
    '#!/bin/sh' \
    'case "$1" in' \
    '  *Username*github.com*) printf "%s\\n" "x-access-token" ;;' \
    '  *Password*github.com*) printf "%s\\n" "$GITHUB_PAT" ;;' \
    '  *) exit 1 ;;' \
    'esac' \
    > /usr/local/bin/git-askpass \
    && chmod 0755 /usr/local/bin/git-askpass

# No xterm-ghostty terminfo needed: compose fixes TERM=xterm-256color for all
# exec sessions (client TERM is not forwarded through `docker compose exec`),
# and xterm-256color/tmux-256color are in the base image's terminfo database.

# The single non-root user, with passwordless sudo so the agent can install
# dependencies and start/stop services inside the sandbox. The node base image
# already owns UID/GID 1000 (`node`), so that account is renamed/reused
# instead of colliding with it.
RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
      GROUP_NAME="$(getent group "${USER_GID}" | cut -d: -f1)"; \
    else \
      groupadd --gid "${USER_GID}" "${USERNAME}"; \
      GROUP_NAME="${USERNAME}"; \
    fi; \
    if id "${USERNAME}" >/dev/null 2>&1; then \
      usermod -s /bin/zsh "${USERNAME}"; \
    elif getent passwd "${USER_UID}" >/dev/null; then \
      EXISTING="$(getent passwd "${USER_UID}" | cut -d: -f1)"; \
      usermod -l "${USERNAME}" -d "/home/${USERNAME}" -m "${EXISTING}"; \
      if [ "${GROUP_NAME}" != "${USERNAME}" ]; then groupmod -n "${USERNAME}" "${GROUP_NAME}"; fi; \
      usermod -g "${USERNAME}" -s /bin/zsh "${USERNAME}"; \
    else \
      useradd --uid "${USER_UID}" --gid "${GROUP_NAME}" -m -s /bin/zsh "${USERNAME}"; \
    fi; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"; \
    chmod 0440 "/etc/sudoers.d/${USERNAME}"; \
    mkdir -p "/home/${USERNAME}" "/home/${USERNAME}/.config/opencode" \
             "/home/${USERNAME}/.agents/skills" \
             "/home/${USERNAME}/.local/share/opencode" /workspace "${PNPM_HOME}"; \
    chown -R "${USER_UID}:${USER_GID}" "/home/${USERNAME}" /workspace "${PNPM_HOME}"

# Copy user dotfiles and entrypoint as root so ownership/mode are correct;
# --chmod is BuildKit-only, so mode is set explicitly here (legacy builder).
COPY --chown=${USER_UID}:${USER_GID} .zshrc "/home/${USERNAME}/.zshrc"
COPY --chown=${USER_UID}:${USER_GID} .tmux.conf "/home/${USERNAME}/.tmux.conf"
COPY --chown=${USER_UID}:${USER_GID} entrypoint.sh /usr/local/bin/sandbox-entrypoint
RUN chmod 0755 /usr/local/bin/sandbox-entrypoint

USER ${USERNAME}
WORKDIR /workspace

# oh-my-zsh, once, for the only user (needs git + curl from the layer above).
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && zsh -i -c 'node --version && pnpm --version && uv --version && opencode --version && tmux -V && git --version'

EXPOSE 4096

# Seeds host config, sets git identity, then runs CMD (idle by default).
ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
CMD ["sleep", "infinity"]
