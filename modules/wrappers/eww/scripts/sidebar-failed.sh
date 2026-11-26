#!/usr/bin/env bash

# Prints failed system and user units as JSON.

failed() {
    systemctl "$@" list-units --state=failed --no-legend --plain 2>/dev/null | cut -d' ' -f1
}

units=$(printf '%s\n%s\n' "$(failed --system)" "$(failed --user)" | sed '/^$/d')
if [ -z "$units" ]; then
    jq -nc '{text: "SYSOK", tooltip: "No failed units", class: "ok"}'
else
    jq -nc --arg text "SYSF:$(wc -l <<<"$units")" --arg tooltip "$units" \
        '{$text, $tooltip, class: "degraded"}'
fi
