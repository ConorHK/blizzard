# shellcheck shell=bash
# Names this terminal's Herdr tab after a session's first prompt, once per session.
# Usage: herdr-tab-name <session> <prompt>; returns at once and names the tab in the background.
set -euo pipefail

[ -n "${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null && command -v herdr-app >/dev/null || exit 0
session=${1:?usage: herdr-tab-name <session> <prompt>}
prompt=${2:-}
case $prompt in "" | /* | !*) exit 0 ;; esac

me=$HC_TERMINAL_ID
labels=$(hc get "$me" | jq -c '.labels // {}')
tab=$(jq -r '."herdr.tab" // empty' <<<"$labels")
[ -n "$tab" ] || exit 0
[ "$(jq -r '."herdr.named" // empty' <<<"$labels")" != "$session" ] || exit 0
hc label "$me" "herdr.named=$session" >/dev/null

# Herdr calls an unnamed tab by its number, or by its agent's title: "Claude Code", or pi's "<pi sign> - <folder>".
unnamed() {
	local name
	name=$(herdr-app ls 2>/dev/null | jq -r --arg tab "$tab" '.spaces[].tabs[] | select(.id == $tab) | .name')
	[[ $name =~ ^[0-9]*$ || $name == "Claude Code" || $name == $'\u03c0 - '* || $name == "pi - "* ]]
}
unnamed || exit 0

# Detached, so the prompt is not held up; the namer sees no terminal, so its own hooks stay quiet.
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
