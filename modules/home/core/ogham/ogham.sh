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
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o LogLevel=ERROR}

warn() {
  echo "ogham: $*" >&2
}

# Clones into $vault, keeping files already there.
adopt() {
  tmp=$(mktemp -d)
  if git clone -q --no-checkout "$remote" "$tmp/repo"; then
    mkdir -p "$vault"
    mv "$tmp/repo/.git" "$vault/.git"
    git -C "$vault" reset -q
    git -C "$vault" ls-files -dz | (cd "$vault" && xargs -0r git checkout --)
  else
    warn "clone of $remote failed; retrying next switch"
  fi
  rm -rf "$tmp"
}

init() {
  if [ -d "$vault/.git" ]; then
    if [ -n "$remote" ]; then
      git -C "$vault" remote set-url origin "$remote" 2>/dev/null \
        || git -C "$vault" remote add origin "$remote"
    fi
  elif [ -n "$remote" ]; then
    adopt
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
    warn "pull failed; resolve $vault by hand"
    exit 1
  fi
  git push -q origin "$branch"
}

case $cmd in
  init) init ;;
  sync) sync ;;
  *) usage ;;
esac
