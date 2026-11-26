#!/usr/bin/env bash

# Waybar hides a custom module whenever its exec exits non-zero, discarding any output,
# so every path that has something to show must print it and exit 0.

FLAKE_DIR="${1:-.}"
REMOTE="${2:-origin}"
BRANCH="${3:-main}"
ICON_UP_TO_DATE="FLKOK"
ICON_OUTDATED="FKUPD"
ICON_ERROR="FKERR"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-15}"

emit() {
    printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$1" "$2" "$3"
    exit 0
}

# Skip the snapshot so a poll never rewrites the working-copy commit under the user.
j() {
    jj --ignore-working-copy --no-pager --color never "$@"
}

count() {
    j log --no-graph -r "$1" -T 'commit_id ++ "\n"' 2>/dev/null | wc -l
}

day() {
    j log --no-graph -r "$1" -T 'committer.timestamp().format("%Y-%m-%d")' 2>/dev/null
}

cd "$FLAKE_DIR" || emit "$ICON_ERROR" "No such directory: $FLAKE_DIR" "error"

if ! j root > /dev/null 2>&1; then
    emit "$ICON_ERROR" "Not a jj repository" "error"
fi

# Never block on a dead network or an interactive credential prompt.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=5 -o BatchMode=yes}"
export GIT_TERMINAL_PROMPT=0

STALE=""
if ! timeout -k 5 "$FETCH_TIMEOUT" jj --ignore-working-copy git fetch --quiet --remote "exact:$REMOTE" --branch "exact:$BRANCH" 2>/dev/null; then
    STALE=", offline, last known"
fi

UPSTREAM="remote_bookmarks(exact:\"$BRANCH\", exact:\"$REMOTE\")"
BEHIND="::$UPSTREAM ~ ::@"
AHEAD="(::@ ~ ::$UPSTREAM) ~ empty()"

if [ "$(count "$UPSTREAM")" -ne 1 ]; then
    emit "$ICON_ERROR" "No commit for $BRANCH@$REMOTE" "error"
fi

COMMITS_BEHIND=$(count "$BEHIND")
COMMITS_AHEAD=$(count "$AHEAD")

if [ "$COMMITS_BEHIND" -eq 0 ] && [ "$COMMITS_AHEAD" -eq 0 ]; then
    emit "$ICON_UP_TO_DATE" "Up to date ($(day "$UPSTREAM"))$STALE" "up-to-date"
elif [ "$(count "($BEHIND) & files(root:\"flake.lock\")")" -gt 0 ]; then
    emit "$ICON_OUTDATED" "Updates available ($(day "$UPSTREAM"))$STALE" "needs-update"
elif [ "$COMMITS_BEHIND" -gt 0 ]; then
    emit "$ICON_OUTDATED" "$COMMITS_BEHIND commit(s) behind remote$STALE" "sync-issue"
else
    emit "$ICON_UP_TO_DATE" "$COMMITS_AHEAD commit(s) ahead of remote$STALE" "sync-issue"
fi
