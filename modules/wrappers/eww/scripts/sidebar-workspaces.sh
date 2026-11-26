#!/usr/bin/env bash

# Prints the workspace list as JSON on start and after every Hyprland event that changes it.

emit() {
    local monitors
    monitors=$(hyprctl monitors -j) || return 0
    hyprctl workspaces -j | jq -c --argjson m "$monitors" '
        ($m | map(select(.focused)) | first | .activeWorkspace.id) as $focus
        | ($m | map(.activeWorkspace.id)) as $shown
        | map(select(.id > 0))
        | sort_by(.id)
        | map(.id as $id | {
            name,
            monitor,
            focused: ($id == $focus),
            visible: any($shown[]; . == $id)
          })'
}

socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

while true; do
    emit
    while read -r line; do
        case $line in
            workspace* | focusedmon* | createworkspace* | destroyworkspace* \
                | moveworkspace* | renameworkspace* | monitoradded* | monitorremoved*)
                emit
                ;;
        esac
    done < <(socat -u "UNIX-CONNECT:$socket" -)
    # Hyprland restarted or the socket is not up yet.
    sleep 1
done
