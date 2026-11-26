#!/usr/bin/env bash

# Usage: sidebar-thumb CONFIG_DIR [WORKSPACE...]
# Captures the workspaces, or all of them, into the eww thumbs map.

# eww kills hover commands after 200ms whatever :timeout says, so run detached.
if [ -z "${SIDEBAR_THUMB_DETACHED:-}" ]; then
    SIDEBAR_THUMB_DETACHED=1 setsid -f "$0" "$@" >/dev/null 2>&1
    exit 0
fi

config=$1
shift
dir="$XDG_RUNTIME_DIR/ws-thumbs"
mkdir -p "$dir"

# A capture already running covers this one, so skip instead of queueing.
exec 9>"$dir/.lock"
flock -n 9 || exit 0

paths=$(ws-thumbs "$dir" "$@") || exit 0
current=$(eww --config "$config" get thumbs 2>/dev/null) || true
[ -n "$current" ] || current='{}'
eww --config "$config" update \
    thumbs="$(jq -nc --argjson a "$current" --argjson b "$paths" '$a + $b')"
