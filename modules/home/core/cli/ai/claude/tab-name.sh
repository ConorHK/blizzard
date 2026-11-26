# shellcheck shell=bash
# UserPromptSubmit hook: hands the prompt to herdr-tab-name.
# Usage: claude-tab-name, with the hook's JSON on stdin.
set -euo pipefail

command -v herdr-tab-name >/dev/null || exit 0
input=$(cat)
# Its stdout would land in the model's context.
herdr-tab-name "$(jq -r '.session_id' <<<"$input")" "$(jq -r '.prompt' <<<"$input")" >/dev/null
