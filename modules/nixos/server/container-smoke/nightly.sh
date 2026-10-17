#!/usr/bin/env bash
# Smoke tests or queues renovate branches.
set -euo pipefail

host=${1:-$(hostname)}
repo=${GITHUB_REPOSITORY:?}
# Branch copies of ci.sh may be stale.
ci=$(mktemp)
cp "$(dirname "$0")/ci.sh" "$ci"
start=$(git rev-parse HEAD)
trap 'git checkout -q --detach "$start"; rm -f "$ci"' EXIT

open=1
if ! reason=$(container-smoke-window); then
  echo "Skipped: $reason"
  open=0
fi

status() {
  gh api --silent "repos/$repo/statuses/$1" -f context=container-smoke \
    -f state="$2" -f description="${3:0:140}"
}

# grep -q exit trips pipefail via SIGPIPE.
changes_image() {
  git diff "$(git merge-base "$1" origin/main)" "$1" -- '*.nix' |
    grep -E '^[+-][[:space:]]*image =' >/dev/null
}

mapfile -t branches < <(gh api --paginate "repos/$repo/branches" \
  --jq '.[] | select(.name | startswith("renovate/")) | "\(.name) \(.commit.sha)"')

for line in "${branches[@]}"; do
  read -r branch sha <<<"$line"
  read -r decided marked < <(gh api "repos/$repo/commits/$sha/statuses" \
    --jq '[.[] | select(.context == "container-smoke")] |
      "\(map(select(.state != "pending")) | length) \(length)"')
  ((decided == 0)) || continue
  if ((open)) && ! reason=$(container-smoke-window); then
    echo "Stopped: $reason"
    open=0
  fi

  git fetch -q origin "$sha"
  if ((!open)); then
    if ((marked == 0)) && changes_image "$sha"; then
      status "$sha" pending "Waits for the next maintenance window"
      echo "$branch waits for the window."
    fi
    continue
  fi

  echo "::group::$branch"
  git checkout -q --detach "$sha"
  rc=0
  out=$(bash "$ci" "$host" </dev/null 2>&1) || rc=$?
  echo "$out"
  echo "::endgroup::"

  case $rc in
    0) status "$sha" success "$(tail -n 1 <<<"$out")" ;;
    75)
      status "$sha" pending "Waits for the next maintenance window"
      echo "Window closed; $branch waits for tomorrow."
      open=0
      ;;
    *) status "$sha" failure "$(grep -m 1 ': fail' <<<"$out" || tail -n 1 <<<"$out")" ;;
  esac
done
