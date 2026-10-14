#!/usr/bin/env bash

# Waybar spawns exec/on-click commands through a shell and reports failures nowhere the
# user will see them, so a name that resolves to nothing is silently dead config.

set -euo pipefail

# Resolved from the session PATH at runtime rather than pinned to a store path.
ALLOWED=(test wpctl)

status=0

for config in "$@"; do
  while read -r command; do
    [ -n "$command" ] || continue

    case "$command" in
      /nix/store/*)
        if [ ! -x "$command" ]; then
          echo "$config: $command is not executable" >&2
          status=1
        fi
        continue
        ;;
    esac

    for allowed in "${ALLOWED[@]}"; do
      if [ "$command" = "$allowed" ]; then
        continue 2
      fi
    done

    echo "$config: '$command' is neither a store path nor an allowed system command" >&2
    status=1
  done < <(jq -r '.. | objects | to_entries[]
                  | select(.key | test("^(exec|exec-if|on-click.*|on-scroll.*|on-update|on-timer)$"))
                  | select(.value | type == "string")
                  | .value | split(" ")[0]' "$config")
done

exit "$status"
