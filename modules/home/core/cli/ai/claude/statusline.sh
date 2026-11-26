# shellcheck shell=bash
# Claude Code status line: model, effort, context use and plan limits.
# Usage: claude-statusline, with the status JSON on stdin.
set -euo pipefail

jq -r --argjson now "$(date +%s)" '
  def paint($p): (if $p >= 80 then "131" elif $p >= 50 then "137" else "102" end) as $c
    | "\u001b[38;5;\($c)m\($p | floor)%\u001b[0m";
  def left($at): ($at - $now) as $s
    | if $s <= 0 then "" elif $s < 3600 then " \($s / 60 | floor)m"
      elif $s < 86400 then " \($s / 3600 | floor)h\($s % 3600 / 60 | floor)m"
      else " \($s / 86400 | floor)d\($s % 86400 / 3600 | floor)h" end;
  def limit($name; $r): if $r.used_percentage == null then empty
    else "\($name) \(paint($r.used_percentage))\u001b[38;5;102m\(left($r.resets_at // 0))\u001b[0m" end;
  [
    ([.model.display_name, .effort.level] | map(select(. != null)) | join(" ")),
    (.context_window.used_percentage | if . == null then empty else "ctx \(paint(.))" end),
    limit("5h"; .rate_limits.five_hour // {}),
    limit("7d"; .rate_limits.seven_day // {})
  ] | map(select(. != "")) | join(" | ")
'
