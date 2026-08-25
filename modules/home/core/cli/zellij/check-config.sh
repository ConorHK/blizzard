#!/usr/bin/env bash
# Hands the generated config to zellij's own validator, which parses the KDL and
# rejects unknown modes, actions and plugin blocks.
set -euo pipefail

conf=$1

zellij --config "$conf" setup --check > report

# A config zellij cannot find is reported without a non-zero exit, so the
# validator only means anything once we know it read the file.
if ! grep -q '\[CONFIG FILE\]: Well defined.' report; then
  echo "zellij did not accept $conf:" >&2
  cat report >&2
  exit 1
fi

fail() {
  echo "FAIL $1" >&2
  exit 1
}

# The shell comes from core, not from this module: proves the two still merge.
grep -q 'default_shell "fish"' "$conf" || fail "panes do not open in fish"

grep -q 'bind "Ctrl t" { SwitchToMode "Tmux"; }' "$conf" ||
  fail "Ctrl-t no longer reaches the command mode"

plugin=$(sed -n 's|.*location="file://\([^"]*\)".*|\1|p' "$conf")
[ -n "$plugin" ] || fail "no autolock plugin in the config"
[ -f "$plugin" ] || fail "the autolock plugin is missing from the store: $plugin"

grep -q 'triggers "nvim|vim|cnvim"' "$conf" || fail "autolock watches nothing"

echo "all checks passed"
