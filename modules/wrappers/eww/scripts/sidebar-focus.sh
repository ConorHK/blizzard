#!/usr/bin/env bash

# Usage: sidebar-focus WORKSPACE
# Hyprland here reads IPC dispatches as Lua, so the name is checked before it goes into one.

name=$1
if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "sidebar-focus: bad workspace name: $name" >&2
    exit 1
fi
hyprctl dispatch "hl.dsp.focus({ workspace = \"$name\" })"
