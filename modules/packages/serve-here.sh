# shellcheck shell=bash
set -euo pipefail

port=${1:-8000}
if ! [[ "$port" =~ ^[0-9]{1,5}$ ]] || ((10#$port < 1 || 10#$port > 65535)); then
  echo "Invalid port" >&2
  exit 2
fi

child=""
# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ -n "$child" ]; then
    kill "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
  iptables -D nixos-fw -p tcp --dport "$port" -j ACCEPT
}

iptables -I nixos-fw -p tcp --dport "$port" -j ACCEPT
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python -m uploadserver "$@" &
child=$!
status=0
wait "$child" || status=$?
child=""
exit "$status"
