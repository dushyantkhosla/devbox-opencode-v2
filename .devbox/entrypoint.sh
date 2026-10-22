#!/bin/sh
# Seeds the checkout's config (bound read-only at /seed by devbox.compose.yml)
# into the writable config/skills volumes, re-seeding whenever the seed content
# itself changes. Then sets git identity and idles. The OpenCode server is
# started manually from a tmux shell (see README).
set -eu

config="$HOME/.config/opencode"
skills="$HOME/.agents/skills"

# Content fingerprint of the given seed paths: sha256 over paths and bytes,
# mtimes ignored. Identical content re-checked out does not re-seed; an edited,
# added or removed seed file does.
fingerprint() {
    find "$@" -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum | cut -d' ' -f1
}

# seed DEST MARKER LEGACY SRC...
#   DEST    volume directory the seed is copied into
#   MARKER  records "<fingerprint>" then the top-level entries the seed wrote,
#           one per line, so a later re-seed knows what to replace
#   LEGACY  what to do with a marker from the host-seeded era (empty file, no
#           fingerprint, so the volume may hold content from the host): "wipe"
#           clears DEST first (skills volume: nothing in it is ours), "names"
#           clears the top-level entries the seed is about to write (config
#           volume: replaces host-seeded agents/commands/plugins while runtime
#           files such as cli.json survive)
#   SRC...  seed paths under /seed; pass "DIR/." to copy DIR's children into
#           DEST (skills), or a plain path to copy that dir/file as one entry
#           (config).
#
# A re-seed removes exactly what the previous seed wrote, so renamed/removed
# seed entries cannot linger while anything the container added survives.
seed() {
    dest=$1
    marker=$2
    legacy=$3
    shift 3

    hash=$(fingerprint "$@")
    if [ -f "$marker" ] && [ "$(head -n 1 "$marker")" = "$hash" ]; then
        return 0
    fi

    if [ ! -f "$marker" ]; then
        : # fresh volume, nothing to clear
    elif [ -z "$(head -n 1 "$marker")" ]; then
        # Unrecorded content, i.e. seeded from the host in a previous devbox
        # generation: drop it, see LEGACY above.
        case $legacy in
            wipe) find "$dest" -mindepth 1 -delete ;;
            names)
                for src in "$@"; do
                    [ "${src%/.}" = "$src" ] && rm -rf "${dest:?}/$(basename "$src")"
                done
                ;;
        esac
    else
        sed 1d "$marker" |
            while IFS= read -r old; do
                [ -n "$old" ] && rm -rf "${dest:?}/$old"
            done
    fi

    entries=""
    for src in "$@"; do
        cp -R "$src" "$dest/"
        if [ "${src%/.}" != "$src" ]; then
            entries="$entries$(ls -A "${src%/.}")
"
        else
            entries="$entries$(basename "$src")
"
        fi
    done
    chmod -R u+rwX "$dest"
    printf '%s\n%s' "$hash" "$entries" >"$marker"
}

seed "$config" "$config/.host-config-seeded" names \
    /seed/opencode.json /seed/agents /seed/commands /seed/plugins
seed "$skills" "$skills/.host-skills-seeded" wipe /seed/skills/.

git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

exec "$@"
