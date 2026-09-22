# shellcheck shell=bash
set -euo pipefail

reject() {
  echo "Unsupported read-only request" >&2
  exit 2
}

command=${1:-}
[ "$#" -gt 0 ] || reject
shift

case "$command" in
ps | images | info | version)
  [ "$#" -eq 0 ] || reject
  exec podman "$command"
  ;;
events)
  [ "$#" -eq 0 ] || reject
  exec podman events --stream=false --since=1h
  ;;
stats)
  [ "$#" -eq 0 ] || reject
  exec podman stats --no-stream
  ;;
inspect | logs | port)
  [ "$#" -ge 1 ] || reject
  name=$1
  shift
  [[ "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || reject
  if [ "$command" = logs ]; then
    [ "$#" -le 1 ] || reject
    lines=${1:-200}
    [[ "$lines" =~ ^[0-9]{1,4}$ ]] || reject
    exec podman logs --tail "$lines" "$name"
  fi
  [ "$#" -eq 0 ] || reject
  if [ "$command" = inspect ]; then
    exec podman inspect --format '{{json .State}}' "$name"
  fi
  exec podman port "$name"
  ;;
*) reject ;;
esac
