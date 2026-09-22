# shellcheck shell=bash disable=SC2088
set -euo pipefail
allow=("${allow[@]}")
ro=("${ro[@]}")
extra=("${extra[@]}")

home=$(readlink -f "$HOME")
cwd=$(readlink -f "$PWD")
case "$home" in
"$cwd" | "$cwd"/*)
  echo "Workspace contains home; refusing" >&2
  exit 1
  ;;
esac
case "$cwd" in
/run | /run/* | /nix | /nix/* | /var)
  echo "Workspace exposes host controls; refusing" >&2
  exit 1
  ;;
esac

args=(
  --ro-bind / /
  --proc /proc
  --dev /dev
  --tmpfs /tmp
  --tmpfs /run
  --tmpfs /nix/var/nix/daemon-socket
  --tmpfs "$home"
  --unsetenv DBUS_SESSION_BUS_ADDRESS
  --unsetenv DBUS_SYSTEM_BUS_ADDRESS
  --unsetenv SSH_AUTH_SOCK
  --unshare-all
  --die-with-parent
)
if [ "${network:-true}" = true ]; then args+=(--share-net); fi
if [ "${new_session:-true}" = true ]; then args+=(--new-session); fi

expand() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then p="$HOME/${p#"~/"}"; fi
  printf '%s' "$p"
}

bind() {
  local flag="$1" p="$2" src dest
  if [ ! -e "$p" ]; then
    echo "Skipping missing path: $p" >&2
    return 0
  fi
  src=$(readlink -f "$p")
  dest="$(readlink -f "$(dirname "$p")")/$(basename "$p")"
  args+=("$flag" "$src" "$dest")
}

# DNS configuration can live under /run.
if [ -e /etc/resolv.conf ]; then
  args+=(--ro-bind /etc/resolv.conf "$(readlink -f /etc/resolv.conf)")
fi
if [ -d /run/current-system ]; then
  args+=(--ro-bind /run/current-system /run/current-system)
fi
args+=(--dir "/run/user/$(id -u)" --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)")
bind --bind "$cwd"
bind --bind "$HOME/.pi/agent"
# Guard code stays immutable between sessions.
bind --ro-bind "$HOME/.pi/agent/extensions"
bind --ro-bind "$HOME/.nix-profile"
for p in "${allow[@]}"; do bind --bind "$(expand "$p")"; done
for p in "${ro[@]}"; do bind --ro-bind "$(expand "$p")"; done
if [ "${#extra[@]}" -gt 0 ]; then args+=("${extra[@]}"); fi
exec bwrap "${args[@]}" -- "$@"
