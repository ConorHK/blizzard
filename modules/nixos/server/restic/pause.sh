# shellcheck shell=bash
set -euo pipefail
state=${RESTIC_PAUSE_STATE:-/run/restic-backups-service-data/paused}
systemctl=$(command -v systemctl)

control() {
  local scope=$1
  shift
  if [ "$scope" = user ]; then
    runuser -u containers -- env XDG_RUNTIME_DIR="/run/user/$(id -u containers)" \
      "$systemctl" --user "$@"
  else
    "$systemctl" "$@"
  fi
}

pause() {
  local scope=$1 unit=$2 properties key value load="" active=""
  properties=$(control "$scope" show --property=LoadState --property=ActiveState "$unit")
  while IFS='=' read -r key value; do
    case "$key" in
    LoadState) load=$value ;;
    ActiveState) active=$value ;;
    esac
  done <<<"$properties"
  [ "$load" = loaded ] || {
    echo "Cannot load service: $unit" >&2
    exit 1
  }
  case "$active" in
  inactive | failed) return ;;
  active | activating | deactivating | reloading) ;;
  *)
    echo "Unknown service state: $unit" >&2
    exit 1
    ;;
  esac
  printf '%s %s\n' "$scope" "$unit" >>"$state"
  control "$scope" stop "$unit"
}

case "$1" in
stop)
  shift
  : >"$state"
  for spec in "$@"; do
    pause "${spec%%:*}" "${spec#*:}"
  done
  ;;
start)
  [ -f "$state" ] || exit 0
  status=0
  while read -r scope unit; do
    control "$scope" start "$unit" || status=1
  done <"$state"
  exit "$status"
  ;;
*) exit 2 ;;
esac
