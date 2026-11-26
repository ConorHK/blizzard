#!/usr/bin/env bash

# Eww runs click handlers and polls through a shell and only logs failures,
# so a command that resolves to nothing is silently dead config.
# Usage: check-commands <config dir> <runtime package>...

set -euo pipefail

config=$1
shift
search=""
for package in "$@"; do
    search="$search:$package/bin"
done

status=0
commands=$(
    cat "$config"/*.yuck | grep -oE ':on[a-z]+ "[^" ]+' | sed 's/.*"//'
    cat "$config"/*.yuck | grep -E '^\(def(poll|listen) ' | grep -oE '"[^"]+"\)$' | tr -d '")' | cut -d' ' -f1
)
[ -n "$commands" ] || { echo "no commands found in $config" >&2; exit 1; }

while read -r command; do
    if ! PATH="${search#:}" command -v "$command" > /dev/null; then
        echo "'$command' is not in any runtime package" >&2
        status=1
    fi
done < <(sort -u <<<"$commands")

exit "$status"
