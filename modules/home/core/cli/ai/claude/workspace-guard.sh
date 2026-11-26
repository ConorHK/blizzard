# shellcheck shell=bash
# SessionStart hook: warns when another live agent already works in this checkout.
# Usage: claude-workspace-guard, with the hook's JSON on stdin.
set -euo pipefail

[ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null || exit 0
input=$(cat)
case $(jq -r '.source // empty' <<<"$input") in
startup | resume) ;;
*) exit 0 ;;
esac

# A jj workspace or git worktree root, or nothing outside a repo.
root_of() {
	jj workspace root --ignore-working-copy -R "$1" 2>/dev/null ||
		git -C "$1" rev-parse --show-toplevel 2>/dev/null
}

root=$(root_of "$(jq -r '.cwd' <<<"$input")") || exit 0
others=()
# Only agents report a status; an address with a slash lives on another machine.
while IFS=$'\t' read -r address cwd; do
	[ -d "$cwd" ] || continue
	if [ "$(root_of "$cwd" || true)" = "$root" ]; then others+=("$address"); fi
done < <(hc ls 2>/dev/null | jq -r --arg me "$HC_TERMINAL_ID" '
  .terminals[]
  | select(.state == "live" and .status != null)
  | select(.address != $me and (.address | contains("/") | not))
  | [.address, .cwd] | @tsv')

[ ${#others[@]} -gt 0 ] || exit 0
list=${others[*]}
jq -n --arg list "$list" --arg root "$root" '{
  systemMessage: "Agent \($list) already works in this checkout.",
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: "Live agent terminal(s) \($list) already work in \($root). They share its jj working copy, so a commit, squash or rebase here rewrites theirs. Before the first edit, tell the user and move into a workspace of your own."
  }
}'
