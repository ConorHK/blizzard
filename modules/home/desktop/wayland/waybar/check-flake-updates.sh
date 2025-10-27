#!/usr/bin/env bash

FLAKE_DIR="${1:-.}"
REMOTE="${2:-origin}"
BRANCH="${3:-main}"
ICON_UP_TO_DATE="FLKUPD"
ICON_OUTDATED="OUTDAT"
ICON_ERROR="FLKERR"

cd "$FLAKE_DIR" || exit 1

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "{\"text\": \"$ICON_ERROR\", \"tooltip\": \"Not a git repository\"}"
    exit 1
fi

if ! git fetch "$REMOTE" 2>/dev/null; then
    echo "{\"text\": \"$ICON_ERROR\", \"tooltip\": \"Failed to fetch remote\"}"
    exit 1
fi

LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null)
REMOTE_COMMIT=$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null)

if [ -z "$LOCAL_COMMIT" ] || [ -z "$REMOTE_COMMIT" ]; then
    echo "{\"text\": \"$ICON_ERROR\", \"tooltip\": \"Failed to get commit hashes\"}"
    exit 1
fi

LOCAL_LOCK_HASH=$(git rev-parse HEAD:flake.lock 2>/dev/null)
REMOTE_LOCK_HASH=$(git rev-parse "$REMOTE/$BRANCH":flake.lock 2>/dev/null)

LOCAL_DATE=$(git log -1 --format=%ai 2>/dev/null | cut -d' ' -f1)
REMOTE_DATE=$(git log -1 --format=%ai "$REMOTE/$BRANCH" 2>/dev/null | cut -d' ' -f1)
COMMITS_BEHIND=$(git rev-list --count "$REMOTE/$BRANCH"..HEAD 2>/dev/null)

if [ "$LOCAL_LOCK_HASH" = "$REMOTE_LOCK_HASH" ]; then
    TOOLTIP="✓ Up to date ($(echo $LOCAL_DATE | cut -d' ' -f1))"
    TEXT="$ICON_UP_TO_DATE"
    CLASS="up-to-date"
elif [ "$LOCAL_COMMIT" = "$REMOTE_COMMIT" ]; then
    TOOLTIP="󰔄 Updates available ($(echo $REMOTE_DATE | cut -d' ' -f1))"
    TEXT="$ICON_OUTDATED"
    CLASS="needs-update"
else
    if [ "$COMMITS_BEHIND" -gt 0 ]; then
        BEHIND=$(git rev-list --count HEAD.."$REMOTE/$BRANCH" 2>/dev/null)
        TOOLTIP="${BEHIND} commit(s) behind remote"
        TEXT="$ICON_OUTDATED"
    else
        AHEAD=$(git rev-list --count "$REMOTE/$BRANCH"..HEAD 2>/dev/null)
        TOOLTIP="${AHEAD} commit(s) ahead of remote"
        TEXT="$ICON_UP_TO_DATE"
    fi
    CLASS="sync-issue"
fi

echo "{\"text\": \"$TEXT\", \"tooltip\": \"$TOOLTIP\", \"class\": \"$CLASS\"}"
