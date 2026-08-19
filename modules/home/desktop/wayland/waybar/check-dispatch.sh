#!/usr/bin/env bash

# Waybar's Hyprland module hardcodes dispatcher strings. This Hyprland parses IPC
# dispatches as Lua, so a legacy string is a syntax error the module logs and swallows:
# clicks silently do nothing. Every dispatch waybar can emit must be in hl.* form.

set -euo pipefail

status=0
lua_seen=0

for package in "$@"; do
  for binary in "$package"/bin/* "$package"/bin/.*; do
    [ -f "$binary" ] || continue

    dispatches=$(strings -a "$binary" | grep -E '^dispatch ' || true)
    [ -n "$dispatches" ] || continue

    legacy=$(printf '%s\n' "$dispatches" | grep -vE '^dispatch hl\.' || true)
    if [ -n "$legacy" ]; then
      echo "$binary can emit legacy dispatches Hyprland cannot parse:" >&2
      printf '%s\n' "$legacy" | sed 's/^/  /' >&2
      status=1
    fi

    if printf '%s\n' "$dispatches" | grep -E '^dispatch hl\.' > /dev/null; then
      lua_seen=1
    fi
  done
done

# Guard against passing vacuously if the patch, or the module, stops producing them.
if [ "$lua_seen" -eq 0 ]; then
  echo "no 'dispatch hl.*' strings found in any waybar binary" >&2
  status=1
fi

exit "$status"
