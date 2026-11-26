#!/usr/bin/env bash

# Prints the first battery's charge as JSON, or nothing to show without one.

for battery in /sys/class/power_supply/BAT*; do
    [ -r "$battery/capacity" ] || continue
    capacity=$(<"$battery/capacity")
    status=$(<"$battery/status")
    prefix=b
    [ "$status" = Charging ] && prefix=c
    class=good
    if [ "$capacity" -le 15 ]; then
        class=critical
    elif [ "$capacity" -le 30 ]; then
        class=warning
    fi
    [ "$status" = Charging ] && class="$class charging"
    jq -nc --arg text "$prefix:$capacity%" --arg tooltip "$status" --arg class "$class" \
        '{$text, $tooltip, $class}'
    exit 0
done
jq -nc '{text: "", tooltip: "", class: ""}'
