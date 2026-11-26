#!/usr/bin/env bash

# Hyprland here reads IPC dispatches as Lua and a bad one fails silently, so make
# Hyprland's own Lua state judge the dispatch sidebar-focus sends.
# The expression is never called: without a compositor it would fail on workspace state.
# Usage: check-lua-api <Hyprland binary> <sidebar-focus script>

set -euo pipefail

hyprland=$1
focus=$2

template=$(grep -oE 'hl\.dsp\.[a-z_.]+\(\{[^}]*\}\)' "$focus" | sed 's/\\"/"/g')
[ -n "$template" ] || { echo "no dispatch found in $focus" >&2; exit 1; }
expression=${template//\$name/1}
dispatcher=${expression%%(*}

config=$(mktemp --suffix=.lua)
cat > "$config" <<EOF
assert(type($dispatcher) == "function", [[no such dispatcher: $dispatcher]])
assert(load([[return hl.dispatch($expression)]]), [[does not parse: $expression]])
EOF
sed 's/^/  /' "$config" >&2

XDG_RUNTIME_DIR=$(mktemp -d) HOME=$(mktemp -d) "$hyprland" --verify-config -c "$config"
