#!/usr/bin/env bash
# Loads the generated tmux.conf into a real server and checks that every
# setting and binding the zellij config used to provide is present, that the
# C-hjkl passthrough classifies commands the way zellij's autolock plugin did,
# and that the scrollback binding actually captures a pane's history.
set -euo pipefail

conf=$1
fake_nvim=$2 # a binary literally named `nvim`, so panes report that name
fake_editor=$3
sesh=$4

declare -a failures=()

expect() { # <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    failures+=("$1")
  fi
}

expect_contains() { # <description> <needle> <haystack>
  if [[ $3 == *"$2"* ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       missing:  %s\n       in:       %s\n' "$1" "$2" "$3"
    failures+=("$1")
  fi
}

# tmux re-quotes bindings on the way out, so pull the command out by column
# rather than matching the raw line.
binding() { # <table> <key>
  tmux list-keys -T "$1" | awk -v table="$1" -v key="$2" '
    {
      for (i = 1; i <= NF; i++) if ($i == "-T") break
      if ($(i + 1) != table || $(i + 2) != key) next
      command = $(i + 3)
      for (j = i + 4; j <= NF; j++) command = command " " $j
      print command
      exit
    }'
}

option() { tmux show-options -gqv "$1"; }

# A pane per classification branch: one that owns C-hjkl and one that does not.
# `exec` so the pane's foreground process is the command and not the shell.
tmux -f "$conf" new-session -d -x 80 -y 24 -s probe "exec $fake_nvim $PWD/keys" 2> config-errors
tmux split-window -t probe:1 "exec sleep 600"
expect "the config loads without errors" "" "$(cat config-errors)"

printf '\n# options\n'
expect "prefix" "C-t" "$(option prefix)"
expect "mode-keys" "vi" "$(option mode-keys)"
expect "status-keys" "vi" "$(option status-keys)"
expect "mouse" "on" "$(option mouse)"
expect "clock-mode-style" "24" "$(option clock-mode-style)"
expect "base-index" "1" "$(option base-index)"
expect "pane-base-index" "1" "$(option pane-base-index)"
expect "escape-time" "0" "$(option escape-time)"
expect "history-limit" "50000" "$(option history-limit)"
expect "focus-events" "on" "$(option focus-events)"
expect "default-terminal" "tmux-256color" "$(option default-terminal)"
expect "status-position" "top" "$(option status-position)"
expect "renumber-windows" "on" "$(option renumber-windows)"
expect "allow-passthrough" "on" "$(option allow-passthrough)"
expect "set-clipboard" "on" "$(option set-clipboard)"
expect_contains "terminal-features asks for truecolour" "*:RGB" "$(option terminal-features)"

shell=$(option default-shell)
expect_contains "panes open in fish" "/bin/fish" "$shell"
if [ -x "$shell" ]; then
  printf 'ok   %s\n' "the configured shell exists"
else
  printf 'FAIL %s\n' "the configured shell exists: $shell"
  failures+=("the configured shell exists")
fi

# Stylix themes tmux through a sourced base16 file rather than inline colours.
expect_contains "stylix colours are sourced" "source-file" "$(cat "$conf")"

printf '\n# prefix bindings\n'
expect "C-t passes the prefix through" "send-prefix" "$(binding prefix C-t)"
expect "v splits to the right" 'split-window -h -c "#{pane_current_path}"' "$(binding prefix v)"
expect "h splits downwards" 'split-window -v -c "#{pane_current_path}"' "$(binding prefix h)"
expect "c opens a window in the same directory" 'new-window -c "#{pane_current_path}"' "$(binding prefix c)"
expect "z zooms" "resize-pane -Z" "$(binding prefix z)"
expect "x closes a pane without confirming" "kill-pane" "$(binding prefix x)"
expect "& closes a window without confirming" "kill-window" "$(binding prefix '&')"
expect "d detaches" "detach-client" "$(binding prefix d)"
expect "n and p walk the window list" "next-window previous-window" \
  "$(binding prefix n) $(binding prefix p)"
expect "o enters copy mode" "copy-mode" "$(binding prefix o)"
expect_contains "/ searches the scrollback" "search-backward" "$(binding prefix /)"
expect_contains "r renames the window" "rename-window" "$(binding prefix r)"
expect "s lists sessions to switch between" "choose-tree -Zs" "$(binding prefix s)"
expect_contains "Q confirms before killing the session" "confirm-before" "$(binding prefix Q)"
expect "y copies the selection in copy mode" "send-keys -X copy-selection-and-cancel" \
  "$(binding copy-mode-vi y)"
expect "C-b is no longer bound" "" "$(binding prefix C-b)"

for pair in h:L j:D k:U l:R; do
  key=${pair%%:*}
  flag=${pair##*:}
  expect "prefix C-$key moves focus" "select-pane -$flag" "$(binding prefix "C-$key")"
  expect "prefix ${key^^} resizes" "resize-pane -$flag 5" "$(binding prefix "${key^^}")"
done

printf '\n# focus keys outside the prefix\n'
for pair in h:L:Left j:D:Down k:U:Up l:R:Right; do
  IFS=: read -r key flag arrow <<< "$pair"
  expect "C-$arrow moves focus" "select-pane -$flag" "$(binding root "C-$arrow")"
  expect_contains "C-$key is conditional" "send-keys C-$key" "$(binding root "C-$key")"
  expect_contains "C-$key falls back to moving focus" "select-pane -$flag" "$(binding root "C-$key")"
done

printf '\n# which commands keep C-hjkl for themselves\n'
guard=$(binding root C-h)
pattern=${guard#*-F \"}
pattern=${pattern%%\" \"send-keys*}
regex=${pattern#'#{m/ri:'}
regex=${regex%',#{pane_current_command}}'}

if [ -z "$regex" ] || [ "$regex" = "$pattern" ]; then
  printf 'FAIL could not read the passthrough pattern out of: %s\n' "$guard"
  exit 1
fi

for command in nvim vim view nvim-wrapped .nvim-wrapped cnvim fzf zoxide atuin; do
  expect "$command keeps C-hjkl" "1" "$(tmux display-message -p "#{m/ri:$regex,$command}")"
done
for command in fish bash sh git ssh less htop; do
  expect "$command yields C-hjkl to tmux" "0" "$(tmux display-message -p "#{m/ri:$regex,$command}")"
done

printf '\n# the same rule against live panes\n'
expect "an editor pane reports its own name" "nvim" \
  "$(tmux display-message -t probe:1.1 -p '#{pane_current_command}')"
expect "an editor pane keeps C-hjkl" "1" "$(tmux display-message -t probe:1.1 -p "$pattern")"
expect "a plain pane yields C-hjkl" "0" "$(tmux display-message -t probe:1.2 -p "$pattern")"

printf '\n# scrollback capture\n'
scrollback=$(binding prefix e)
scrollback=${scrollback#run-shell }
expect_contains "e runs the scrollback helper" "tmux-scrollback" "$scrollback"

printf '#!/bin/sh\necho SCROLLBACK-MARKER\nexec sleep 600\n' > marker
chmod +x marker
tmux new-window -t probe -n sb "exec $PWD/marker"
pane=$(tmux display-message -t probe:sb -p '#{pane_id}')
for _ in $(seq 1 100); do
  tmux capture-pane -p -t "$pane" | grep -q SCROLLBACK-MARKER && break
  sleep 0.1
done

# Its own TMPDIR so the captured file can be found without guessing its name.
mkdir -p captures
TMPDIR=$PWD/captures TMUX_PANE=$pane EDITOR=$fake_editor "$scrollback"
for _ in $(seq 1 100); do
  compgen -G "captures/*.opened" > /dev/null && break
  sleep 0.1
done
expect_contains "e hands the pane's history to \$EDITOR" "SCROLLBACK-MARKER" \
  "$(cat captures/*.opened 2> /dev/null || true)"

printf '\n# sesh\n'
# It is a way into tmux from the shell, so it must stay out of the way once a
# session is already attached.
expect "sesh does nothing when already inside tmux" "" "$(TMUX=fake "$sesh" 2>&1)"

tmux kill-server

if [ ${#failures[@]} -gt 0 ]; then
  printf '\n%d check(s) failed:\n' "${#failures[@]}"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi

printf '\nall checks passed\n'
