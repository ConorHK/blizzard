# shellcheck shell=bash
# SessionStart hook: passes herdr-workspace-guard's warning to the user and the model.
# Usage: claude-workspace-guard, with the hook's JSON on stdin.
set -euo pipefail

command -v herdr-workspace-guard >/dev/null || exit 0
input=$(cat)
case $(jq -r '.source // empty' <<<"$input") in
startup | resume) ;;
*) exit 0 ;;
esac
cwd=$(jq -r '.cwd' <<<"$input")
others=$(herdr-workspace-guard "$cwd")
[ -n "$others" ] || exit 0
jq -n --arg list "$others" --arg cwd "$cwd" '{
  systemMessage: "Agent \($list) already works in this checkout.",
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: "Live agent terminal(s) \($list) already work in the checkout holding \($cwd). They share its jj working copy, so a commit, squash or rebase here rewrites theirs. Before the first edit, tell the user and move into a workspace of your own."
  }
}'
