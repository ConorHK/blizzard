#!/usr/bin/env bash

# Runs check-backups against fixture status dirs.
# Usage: check-backups-tests <check-backups>

set -euo pipefail

check=$1
dir=$(mktemp -d)
status=0

expect() {
    local want_text=$1 want_tooltip=$2 out
    out=$("$check" "$dir")
    if [ "$(jq -r .text <<<"$out")" != "$want_text" ] \
        || ! jq -r .tooltip <<<"$out" | grep -qF -- "$want_tooltip"; then
        echo "want $want_text, '$want_tooltip'; got $out" >&2
        status=1
    fi
}

expect BKOLD "No backup has run yet"

date +%s >"$dir/home.backup"
expect BKOK "home: backup ok 0m ago, drill never ran"

: >"$dir/home.drill"
expect BKOK "home: backup ok 0m ago, drill ok"

echo $(( $(date +%s) - 3 * 86400 )) >"$dir/home.backup"
expect BKOLD "home: backup ok 3d ago"

date +%s >"$dir/home.backup"
printf '%s\n' "3 restored databases are corrupt" "Restore drill compared no files" >"$dir/home.drill"
expect BKERR "drill 3 restored databases are corrupt;Restore drill compared no files"

: >"$dir/home.drill"
: >"$dir/phone.drill"
expect BKOLD "phone: backup never ran, drill ok"

exit "$status"
