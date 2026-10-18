# shellcheck shell=bash
# Exits 0 unless an upgrade or reboot is underway.
set -euo pipefail

[[ $UPGRADES == true ]] || exit 0

# Oneshots stay activating while they run.
state=$(systemctl show -p ActiveState --value nixos-upgrade.service)
if [[ $state != inactive && $state != failed ]]; then
  echo "nixos-upgrade is running"
  exit 1
fi
if [[ -e /run/systemd/shutdown/scheduled ]]; then
  echo "a reboot is pending"
  exit 1
fi
