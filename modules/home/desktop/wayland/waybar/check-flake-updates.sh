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

cd "$FLAKE_DIR" || emit "$ICON_ERROR" "No such directory: $FLAKE_DIR" "error"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    emit "$ICON_ERROR" "Not a git repository" "error"
fi

# Never block on a dead network or an interactive credential prompt.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=5 -o BatchMode=yes}"
export GIT_TERMINAL_PROMPT=0

STALE=""
if ! timeout -k 5 "$FETCH_TIMEOUT" git fetch --quiet --no-tags "$REMOTE" 2>/dev/null; then
    STALE=" — offline, last known"
fi

LOCAL_COMMIT=$(git rev-parse --verify --quiet HEAD)
REMOTE_COMMIT=$(git rev-parse --verify --quiet "$REMOTE/$BRANCH")

if [ -z "$LOCAL_COMMIT" ] || [ -z "$REMOTE_COMMIT" ]; then
    emit "$ICON_ERROR" "No commit for HEAD or $REMOTE/$BRANCH" "error"
fi

LOCAL_LOCK_HASH=$(git rev-parse --verify --quiet HEAD:flake.lock)
REMOTE_LOCK_HASH=$(git rev-parse --verify --quiet "$REMOTE/$BRANCH:flake.lock")

LOCAL_DATE=$(git log -1 --format=%ai 2>/dev/null | cut -d' ' -f1)
REMOTE_DATE=$(git log -1 --format=%ai "$REMOTE/$BRANCH" 2>/dev/null | cut -d' ' -f1)
COMMITS_BEHIND=$(git rev-list --count HEAD.."$REMOTE/$BRANCH" 2>/dev/null)
COMMITS_BEHIND=${COMMITS_BEHIND:-0}

if [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    emit "$ICON_UP_TO_DATE" "✓ Up to date ($LOCAL_DATE)$STALE" "up-to-date"
elif [ -n "$LOCAL_LOCK_HASH" ] && [ "$LOCAL_LOCK_HASH" != "$REMOTE_LOCK_HASH" ]; then
    emit "$ICON_OUTDATED" "󰔄 Updates available ($REMOTE_DATE)$STALE" "needs-update"
elif [ "$COMMITS_BEHIND" -gt 0 ]; then
    emit "$ICON_OUTDATED" "${COMMITS_BEHIND} commit(s) behind remote$STALE" "sync-issue"
else
    AHEAD=$(git rev-list --count "$REMOTE/$BRANCH"..HEAD 2>/dev/null)
    emit "$ICON_UP_TO_DATE" "${AHEAD:-0} commit(s) ahead of remote$STALE" "sync-issue"
fi
