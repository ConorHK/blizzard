#!/usr/bin/env bash

# Usage: sidebar-run units|jj|network|mixer|bluetooth|backups|flake|volume up|down
# Runs the commands behind sidebar clicks and the polled status checks.

# Eww kills click commands after a timeout, so windows start in their own session.
detach() {
    setsid -f "$@" >/dev/null 2>&1
}

hidden='{"text": "", "tooltip": "", "class": ""}'

units() {
    local bold=$'\033[1;34m' reset=$'\033[0m'
    echo "${bold}User units:${reset}"
    systemctl --user list-units --state=failed
    echo "${bold}System units:${reset}"
    systemctl list-units --state=failed
}

jj_status() {
    cd "$HOME/repositories/blizzard" || return
    jj git fetch --remote origin --branch main
    jj --no-pager log -r '@ | main@origin | ::main@origin ~ ::@ | ::@ ~ ::main@origin'
}

case ${1:-} in
    units | jj)
        what=$1
        if [ -z "${SIDEBAR_RUN_POPUP:-}" ]; then
            SIDEBAR_RUN_POPUP=1 detach alacritty --class alacritty-popup -e "$0" "$what"
            exit 0
        fi
        if [ "$what" = units ]; then units; else jj_status; fi
        read -n 1 -s -r -p "Press any key to exit"
        ;;
    network)
        detach alacritty --class alacritty-popup -e nmtui-connect
        ;;
    mixer)
        detach pwvucontrol
        ;;
    bluetooth)
        detach blueman-manager
        ;;
    volume)
        case ${2:-} in
            up) exec wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+ ;;
            down) exec wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        esac
        ;;
    backups)
        if [ -d /var/lib/restic-status ]; then
            exec check-backups /var/lib/restic-status
        fi
        echo "$hidden"
        ;;
    flake)
        if [ -d "$HOME/repositories/blizzard/.jj" ]; then
            exec check-flake-updates "$HOME/repositories/blizzard" origin
        fi
        echo "$hidden"
        ;;
    *)
        echo "usage: sidebar-run units|jj|network|mixer|bluetooth|backups|flake|volume" >&2
        exit 2
        ;;
esac
