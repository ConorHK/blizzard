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
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10 -o LogLevel=ERROR}

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

# Appends one line to a .git/info file once.
add_line() {
  grep -qxF "$2" "$vault/.git/info/$1" 2>/dev/null \
    || echo "$2" >>"$vault/.git/info/$1"
}

# Search, index.md and wins.md are per host; .tmp precedes renames.
exclude() {
  [ -d "$vault/.git" ] || return 0
  mkdir -p "$vault/.git/info"
  for pattern in .zvec-grep/ '*.tmp' /index.md; do
    add_line exclude "$pattern"
  done
  git -C "$vault" rm -q --cached --ignore-unmatch -- index.md
  # Old wins.md stays synced until pi migrates it.
  if grep -qF 'ogham builds this from wins/' "$vault/wins.md" 2>/dev/null; then
    add_line exclude /wins.md
    git -C "$vault" rm -q --cached --ignore-unmatch -- wins.md
  fi
  # Append-only notes merge by keeping both sides.
  for pattern in /wins.md '/topics/*.md'; do
    add_line attributes "$pattern merge=union"
  done
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
  exclude
}

sync() {
  [ -d "$vault/.git" ] || exit 0
  exclude
  cd "$vault" || exit 1
  exec 9>.git/ogham-sync.lock
  flock -n 9 || exit 0

  git add -A
  if ! git diff --cached --quiet; then
    git commit -q -m "ogham: $(uname -n) $(date -u +%FT%TZ)"
  fi

  git remote get-url origin >/dev/null 2>&1 || exit 0
  branch=$(git symbolic-ref --short HEAD)
  if ! git fetch -q origin "$branch"; then
    warn "fetch failed; retrying next run"
    exit 1
  fi
  # Pi reads this file and warns the user.
  stuck=.git/ogham-sync-error
  if ! git rebase -q --autostash FETCH_HEAD; then
    git rebase --abort 2>/dev/null || true
    echo "rebase onto origin/$branch failed; resolve $vault by hand" >"$stuck"
    warn "$(cat "$stuck")"
    exit 1
  fi
  git push -q origin "HEAD:$branch"
  rm -f "$stuck"
}

case $cmd in
  init) init ;;
  sync) sync ;;
  *) usage ;;
esac
