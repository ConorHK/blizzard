# shellcheck shell=bash
# UserPromptSubmit hook: names the herdr tab after the session's first real prompt.
# Usage: claude-tab-name, with the hook's JSON on stdin.
set -euo pipefail

[ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null && command -v herdr-app >/dev/null || exit 0
input=$(cat)
session=$(jq -r '.session_id' <<<"$input")
prompt=$(jq -r '.prompt' <<<"$input")
case $prompt in "" | /* | !*) exit 0 ;; esac

me=$HC_TERMINAL_ID
labels=$(hc get "$me" | jq -c '.labels // {}')
tab=$(jq -r '."herdr.tab" // empty' <<<"$labels")
[ -n "$tab" ] || exit 0
[ "$(jq -r '."claude.named" // empty' <<<"$labels")" != "$session" ] || exit 0
hc label "$me" "claude.named=$session" >/dev/null

# Herdr calls an unnamed tab by its number, and Claude's title fills in "Claude Code".
unnamed() {
	local name
	name=$(herdr-app ls 2>/dev/null | jq -r --arg tab "$tab" '.spaces[].tabs[] | select(.id == $tab) | .name')
	[[ $name =~ ^[0-9]*$ || $name == "Claude Code" ]]
}
unnamed || exit 0

# Detached, so the prompt is not held up; the child sees no terminal, so its own hooks stay quiet.
(
	name=$(
		cd / && env -u HC_TERMINAL_ID timeout 30 claude -p --model haiku --no-session-persistence --setting-sources project \
			"Name this coding task for a terminal tab in 2 to 4 lowercase words. Reply with the name only, no punctuation. Task: ${prompt:0:2000}" |
			head -n1 | tr '[:upper:]' '[:lower:]' | tr -cd '[:lower:][:digit:] -' | cut -c1-32
	)
	if [ -n "$name" ] && unnamed; then
		herdr-app "do" tab.rename --id "$tab" --name "$name"
	fi
) </dev/null >/dev/null 2>&1 &
disown
