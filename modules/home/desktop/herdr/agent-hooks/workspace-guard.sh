# shellcheck shell=bash
# Prints the other live agents that work in the same jj workspace or git worktree as a folder.
# Usage: herdr-workspace-guard <folder>; prints nothing outside Herdr or when the checkout is free.
set -euo pipefail

[ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null || exit 0

root_of() {
	jj workspace root --ignore-working-copy -R "$1" 2>/dev/null ||
		git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

root=$(root_of "${1:?usage: herdr-workspace-guard <folder>}") || exit 0
others=()
# Only agents report a status; an address with a slash lives on another machine.
while read -r address; do
	# The terminal's own cwd is where its shell started; the agent may have moved since.
	cwd=$(hc get "$address" 2>/dev/null | jq -r '.foreground.cwd // .cwd // empty')
	[ -d "$cwd" ] || continue
	if [ "$(root_of "$cwd" || true)" = "$root" ]; then others+=("$address"); fi
done < <(hc ls 2>/dev/null | jq -r --arg me "$HC_TERMINAL_ID" '
  .terminals[]
  | select(.state == "live" and .status != null)
  | select(.address != $me and (.address | contains("/") | not))
  | .address')

[ ${#others[@]} -gt 0 ] || exit 0
echo "${others[*]}"
