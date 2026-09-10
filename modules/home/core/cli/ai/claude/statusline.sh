# shellcheck shell=bash
# Claude Code statusline (binary `claude-statusline`). Reads the statusline JSON
# payload on stdin and prints one line:
#
#   ctx: 84k/1000k 8% · Opus 5 (1M context) xhigh
#
# The context percentage is the point. Answer quality degrades long before the
# window fills, so the number is coloured against a hand-off budget rather than
# against exhaustion: green under 40%, yellow 40-60% (start a fresh session
# soon), red over 60% (hand off now).
#
# `used_percentage` is supplied by Claude Code as an integer 0-100, so this can
# never disagree with /context. It is null until the session's first API
# response.
#
# Every path prints and exits 0: an upstream schema change must degrade to a
# shorter line, never to an error in the UI.

readonly HANDOFF_SOON=40
readonly HANDOFF_NOW=60

input=$(cat)

# Tab-delimited so the model's display name survives as one field.
IFS=$'\t' read -r used pct size model effort <<<"$(
	jq -r '[
    (.context_window.total_input_tokens // 0),
    (.context_window.used_percentage // -1),
    (.context_window.context_window_size // 0),
    (.model.display_name // ""),
    (.effort.level // "")
  ] | @tsv' <<<"$input" 2>/dev/null
)" || :

reset=$'\033[0m'
dim=$'\033[2m'
out=""

if [[ "$pct" =~ ^[0-9]+$ ]] && [[ "$used" =~ ^[0-9]+$ ]] && [[ "$size" =~ ^[0-9]+$ ]]; then
	if [ "$pct" -ge "$HANDOFF_NOW" ]; then
		colour=$'\033[1;91m'
	elif [ "$pct" -ge "$HANDOFF_SOON" ]; then
		colour=$'\033[1;93m'
	else
		colour=$'\033[1;92m'
	fi
	out="${colour}ctx: $((used / 1000))k/$((size / 1000))k ${pct}%${reset}"
fi

meta="$model"
[ -n "$effort" ] && meta="${meta:+$meta }$effort"
[ -n "$meta" ] && out="${out:+$out · }${dim}${meta}${reset}"

printf '%s' "$out"
