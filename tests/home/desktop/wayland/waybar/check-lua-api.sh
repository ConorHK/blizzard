#!/usr/bin/env bash

# The dispatch strings waybar emits are Lua source to this Hyprland. Rebuild each one the
# way waybar's C++ concatenates it, then make Hyprland's own Lua state judge it: the
# expression must parse, and the dispatcher it names must exist. A prefix with no
# completion means upstream added a call site nothing here has ever verified.
#
# The expressions are deliberately never called -- executing a dispatch without a running
# compositor fails on workspace state, which says nothing about waybar being correct.

set -euo pipefail

hyprland=$1
shift

# Binary string -> the arguments waybar appends to it at runtime, one per line.
completions() {
  case "$1" in
    'dispatch hl.dsp.focus({workspace = "name:')
      printf '%s\n' 'test"})' 'test", on_current_monitor = true})'
      ;;
    'dispatch hl.dsp.focus({workspace = ')
      printf '%s\n' '1})' '1, on_current_monitor = true})'
      ;;
    'dispatch hl.dsp.workspace.toggle_special("')
      printf '%s\n' 'magic")'
      ;;
    'dispatch hl.dsp.workspace.toggle_special()')
      printf '%s\n' ''
      ;;
    *)
      return 1
      ;;
  esac
}

status=0
config=$(mktemp --suffix=.lua)

for package in "$@"; do
  for binary in "$package"/bin/* "$package"/bin/.*; do
    [ -f "$binary" ] || continue

    while IFS= read -r prefix; do
      if ! suffixes=$(completions "$prefix"); then
        echo "no completion known for '$prefix' -- new upstream call site?" >&2
        status=1
        continue
      fi

      while IFS= read -r suffix; do
        expression="${prefix#dispatch }$suffix"
        dispatcher="${expression%%(*}"
        {
          echo "assert(type($dispatcher) == \"function\", [[no such dispatcher: $dispatcher]])"
          echo "assert(load([[return hl.dispatch($expression)]]), [[does not parse: $expression]])"
        } >> "$config"
      done <<< "$suffixes"
    done < <(strings -a "$binary" | grep -E '^dispatch ' || true)
  done
done

if [ ! -s "$config" ]; then
  echo "no dispatches found in any waybar binary" >&2
  exit 1
fi

sed 's/^/  /' "$config" >&2

XDG_RUNTIME_DIR=$(mktemp -d) HOME=$(mktemp -d) "$hyprland" --verify-config -c "$config" || status=1

exit "$status"
