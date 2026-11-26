#!/usr/bin/env bash

# Prints the bluetooth state as JSON.

emit() {
    jq -nc --arg text "$1" --arg tooltip "$2" --arg class "$3" '{$text, $tooltip, $class}'
    exit 0
}

show=$(timeout 3 bluetoothctl show 2>/dev/null)
if [[ $show != *Controller* ]]; then
    emit bt:dis "No controller" disabled
fi
if [[ $show == *"Powered: no"* ]]; then
    emit bt:off "Powered off" off
fi

connected=$(timeout 3 bluetoothctl devices Connected 2>/dev/null | cut -d' ' -f3-)
if [ -n "$connected" ]; then
    emit "bt:$(wc -l <<<"$connected")" "$connected" connected
fi
emit bt:on "$(sed -n 's/^\s*Alias: //p' <<<"$show" | head -n 1)" on
