# shellcheck shell=bash
# ogham init VAULT [REMOTE] | ogham sync VAULT

usage() {
  echo "usage: ogham init VAULT [REMOTE] | ogham sync VAULT" >&2
  exit 2
}

[ $# -ge 2 ] || usage
cmd=$1
vault=$2
remote=${3:-}

# Timers and activation cannot answer prompts.
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}

init() {
  if [ -d "$vault/.git" ]; then
    if [ -n "$remote" ]; then
      git -C "$vault" remote set-url origin "$remote" 2>/dev/null \
        || git -C "$vault" remote add origin "$remote"
    fi
  elif [ -e "$vault" ]; then
    echo "ogham: $vault exists without .git; skipping" >&2
  elif [ -n "$remote" ]; then
    git clone -q "$remote" "$vault" \
      || echo "ogham: clone of $remote failed; retrying next switch" >&2
  else
    git init -q -b main "$vault"
  fi
}

sync() {
  [ -d "$vault/.git" ] || exit 0
  cd "$vault" || exit 1
  exec 9>.git/ogham-sync.lock
  flock -n 9 || exit 0

  git add -A
  if ! git diff --cached --quiet; then
    git commit -q -m "ogham: $(uname -n) $(date -u +%FT%TZ)"
  fi

  git remote get-url origin >/dev/null 2>&1 || exit 0
  branch=$(git symbolic-ref --short HEAD)
  if ! git pull -q --rebase --autostash origin "$branch"; then
    git rebase --abort 2>/dev/null || true
    echo "ogham: pull failed; resolve $vault by hand" >&2
    exit 1
  fi
  git push -q origin "$branch"
}

case $cmd in
  init) init ;;
  sync) sync ;;
  *) usage ;;
esac
