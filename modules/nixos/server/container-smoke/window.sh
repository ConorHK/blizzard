# shellcheck shell=bash
# Exits 0 when a smoke run may start now.
set -euo pipefail

read -r START LAST </etc/container-smoke/window
now=$(date +%H:%M)
if [[ $now < $START || $now > $LAST ]]; then
  echo "outside the $START-$LAST maintenance window"
  exit 1
fi

if [[ $UPGRADES == true ]]; then
  opened=$(date -d "today $START" +%s)
  booted=$(($(date +%s) - $(cut -d. -f1 /proc/uptime)))
  # Oneshots never go active; ActiveExitTimestamp stays unset.
  exited=$(systemctl show --timestamp=unix -p ExecMainExitTimestamp --value nixos-upgrade.service)
  exited=${exited#@}
  # A reboot means today's upgrade finished.
  if systemctl is-active --quiet nixos-upgrade.service ||
    { ((booted < opened)) && ((${exited:-0} < opened)); }; then
    echo "waiting for today's nixos-upgrade"
    exit 1
  fi
  if [[ -e /run/systemd/shutdown/scheduled ]]; then
    echo "a reboot is pending"
    exit 1
  fi
fi
