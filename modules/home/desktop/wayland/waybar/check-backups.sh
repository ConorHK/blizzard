#!/usr/bin/env bash

# Summarizes the status files restic jobs write.
# Usage: check-backups <status dir> [max age in seconds]

dir="${1:-/var/lib/restic-status}"
max_age="${2:-172800}"
now=$(date +%s)

# Worst state wins: ok, running, stale, error.
rank=0
text=BKOK
class=ok
raise() {
    if [ "$1" -gt "$rank" ]; then
        rank=$1
        text=$2
        class=$3
    fi
}

ago() {
    local secs=$1
    if [ "$secs" -lt 3600 ]; then
        echo "$((secs / 60))m ago"
    elif [ "$secs" -lt 172800 ]; then
        echo "$((secs / 3600))h ago"
    else
        echo "$((secs / 86400))d ago"
    fi
}

shopt -s nullglob
mapfile -t jobs < <(
    for f in "$dir"/*.backup "$dir"/*.drill; do
        name=${f##*/}
        echo "${name%.*}"
    done | sort -u
)

lines=()
for job in "${jobs[@]}"; do
    if systemctl is-active --quiet "restic-backups-$job.service" 2>/dev/null; then
        raise 1 BKRUN running
        backup="running now"
    elif systemctl is-failed --quiet "restic-backups-$job.service" 2>/dev/null; then
        raise 3 BKERR error
        backup="last run failed"
    elif [ -s "$dir/$job.backup" ]; then
        age=$((now - $(<"$dir/$job.backup")))
        [ "$age" -le "$max_age" ] || raise 2 BKOLD stale
        backup="ok $(ago "$age")"
    else
        raise 2 BKOLD stale
        backup="never ran"
    fi

    if [ ! -e "$dir/$job.drill" ]; then
        drill="never ran"
    elif [ -s "$dir/$job.drill" ]; then
        raise 3 BKERR error
        drill=$(paste -sd ';' "$dir/$job.drill")
    else
        drill="ok"
    fi

    lines+=("$job: backup $backup, drill $drill")
done

if [ "${#jobs[@]}" -eq 0 ]; then
    raise 2 BKOLD stale
    lines=("No backup has run yet")
fi

jq -nc --arg text "$text" --arg class "$class" --arg tooltip "$(printf '%s\n' "${lines[@]}")" \
    '{text: $text, class: $class, tooltip: ($tooltip | rtrimstr("\n"))}'
