#!/usr/bin/env bash

# Prints the network state as JSON, preferring wired over wifi.

emit() {
    jq -nc --arg text "$1" --arg tooltip "$2" --arg class "$3" '{$text, $tooltip, $class}'
    exit 0
}

devices=$(nmcli -t -f TYPE,STATE,DEVICE device 2>/dev/null) || emit "n:?" "NetworkManager is down" ""

ethernet=$(awk -F: '$1 == "ethernet" && $2 == "connected" { print $3; exit }' <<<"$devices")
if [ -n "$ethernet" ]; then
    emit e:con "$ethernet" ethernet
fi

if grep -q '^wifi:connected:' <<<"$devices"; then
    wifi=$(nmcli -t -f IN-USE,SSID,SIGNAL device wifi list --rescan no 2>/dev/null \
        | awk -F: '$1 == "*" { printf "%s (%s%%)", $2, $3; exit }')
    emit w:con "$wifi" wifi
fi

if grep -q ':connecting' <<<"$devices"; then
    emit n:lnk "Connecting" linked
fi
emit n:dis "disconnected" disconnected
