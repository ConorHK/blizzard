#!/usr/bin/env bash

# Runs check-flake-updates against a local jj repo and bare remote.
# Usage: check-flake-updates-tests <check-flake-updates>

set -euo pipefail

check=$1
dir=$(mktemp -d)
status=0
export HOME=$dir JJ_USER=test JJ_EMAIL=test@example.com

expect() {
    local want_text=$1 want_tooltip=$2 out
    out=$("$check" "$dir/local" origin main)
    if [ "$(jq -r .text <<<"$out")" != "$want_text" ] \
        || ! jq -r .tooltip <<<"$out" | grep -qF -- "$want_tooltip"; then
        echo "want $want_text, '$want_tooltip'; got $out" >&2
        status=1
    fi
}

upstream() {
    echo "$2" >"$dir/upstream/$1"
    jj -R "$dir/upstream" commit --quiet -m "$1"
    jj -R "$dir/upstream" bookmark set --quiet main -r @-
    jj -R "$dir/upstream" git push --quiet --bookmark main
}

git init --quiet --bare --initial-branch main "$dir/remote.git"
jj git init --quiet --colocate "$dir/upstream"
jj -R "$dir/upstream" git remote add origin "$dir/remote.git"
jj -R "$dir/upstream" bookmark create --quiet main -r @
upstream flake.lock 1

jj git clone --quiet --colocate "$dir/remote.git" "$dir/local"
expect FLKOK "Up to date"

upstream README 1
expect FKUPD "1 commit(s) behind remote"

upstream flake.lock 2
expect FKUPD "Updates available"

jj -R "$dir/local" new --quiet main@origin
expect FLKOK "Up to date"

echo 1 >"$dir/local/notes"
jj -R "$dir/local" commit --quiet -m notes
expect FLKOK "1 commit(s) ahead of remote"

jj -R "$dir/local" git remote set-url origin "$dir/missing.git"
expect FLKOK "offline, last known"

mkdir "$dir/plain"
out=$("$check" "$dir/plain")
if [ "$(jq -r .text <<<"$out")" != FKERR ]; then
    echo "want FKERR outside a repo; got $out" >&2
    status=1
fi

exit "$status"
