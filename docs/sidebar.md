# Sidebar

Desktops show an eww sidebar on the left edge. It holds the clock, the
workspace strip and the status modules.

```
modules/nixos/desktop/wayland/sidebar.nix   user service: eww daemon, then one window per screen
modules/wrappers/eww/                        eww config and the scripts it runs
modules/packages/ws-thumbs/                  workspace capture for hover thumbnails
```

## Hosts

`wrappers.eww.output` pins the bar to one screen; unset, it opens on every
screen. `wrappers.eww.extraModules` adds host modules below the volume,
such as `battery` on dullahan.

## Workspace strip

`sidebar-workspaces` follows Hyprland's event socket and prints the
workspace list. Each dot is red with focus, teal when shown on a screen
without focus, and dim when it lives on another screen.

Clicking a dot runs `sidebar-focus`, which sends a Lua dispatch, since
Hyprland here reads IPC dispatches as Lua.

## Thumbnails

Entering the strip runs `sidebar-thumb`, which calls `ws-thumbs` to capture
every workspace; hovering a dot captures that one again. `ws-thumbs` uses
Hyprland's workspace capture source with ext-image-copy-capture, so it
captures hidden workspaces too, in about 100 ms each. Each shot gets a fresh
file name under `$XDG_RUNTIME_DIR/ws-thumbs`, because eww caches images by
path, and the `thumbs` variable maps each workspace to its latest shot.

A GTK tooltip does not redraw once open, so it shows the shot that existed
when it opened. Capturing on entry to the strip makes that shot seconds old
at most.

## Status modules

Every module is a command that prints `{"text", "tooltip", "class"}` JSON.
An empty `text` hides the module. `check-backups` and `check-flake-updates`
keep their own fixture tests in `tests/wrappers/eww/`.
