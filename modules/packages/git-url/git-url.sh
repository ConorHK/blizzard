# shellcheck shell=bash
line_anchor() {
  local lines="$1" range_sep="$2"
  case "$lines" in
    "") ;;
    *-*) echo "#L${lines%%-*}${range_sep}${lines##*-}" ;;
    *,*)
      for l in ${lines//,/ }; do printf '#L%s' "$l"; done
      echo
      ;;
    *) echo "#L${lines}" ;;
  esac
}

remote_url=$(git remote get-url origin 2>/dev/null) || {
  echo "Not a git repository or no origin remote" >&2
  exit 1
}

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch="main"

file="" lines=""
if [ $# -ge 1 ]; then
  repo_root=$(git rev-parse --show-toplevel)
  file=$(realpath --relative-to="$repo_root" "$1" 2>/dev/null || echo "$1")
fi
[ $# -ge 2 ] && lines="$2"

case "$remote_url" in
  *github.com*)
    path=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]||; s|\.git$||')
    base="https://github.com/${path}"
    blob="blob"
    range_sep="-L"
    ;;
  *gitlab*)
    path=$(echo "$remote_url" | sed -E 's|.*gitlab[^/]*[:/]||; s|\.git$||')
    base="https://gitlab.com/${path}"
    blob="-/blob"
    range_sep="-"
    ;;
  *)
    echo "Unknown remote: $remote_url" >&2
    exit 1
    ;;
esac

if [ -z "$file" ]; then
  echo "$base"
else
  echo "${base}/${blob}/${branch}/${file}$(line_anchor "$lines" "$range_sep")"
fi
