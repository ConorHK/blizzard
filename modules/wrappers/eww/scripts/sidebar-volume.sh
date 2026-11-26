#!/usr/bin/env bash

# Prints the default sink's volume as JSON on start and after every sink change.

emit() {
    local line volume icon class=""
    line=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 0
    volume=$(awk '{ printf "%d", $2 * 100 + 0.5 }' <<<"$line")
    if [[ $line == *MUTED* ]]; then
        icon=$'\ue04f'
        class=muted
    elif [ "$volume" -lt 34 ]; then
        icon=$'\ue04e'
    elif [ "$volume" -lt 67 ]; then
        icon=$'\ue053'
    else
        icon=$'\ue050'
    fi
    jq -nc --arg text "$icon$volume" --arg class "$class" \
        --arg tooltip "$(wpctl inspect @DEFAULT_AUDIO_SINK@ \
            | sed -n 's/.*node\.description = "\(.*\)"/\1/p' | head -n 1)" \
        '{$text, $tooltip, $class}'
}

emit
pactl subscribe | while read -r line; do
    case $line in
        *"on sink"* | *"on server"*) emit ;;
    esac
done
