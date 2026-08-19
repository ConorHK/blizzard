{
  hyprland.lua.workspacePin = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd("hypr-ws-pin")
    end)
  '';

  flake.modules.homeManager.hypr-workspace-pin =
    { pkgs, ... }:
    let
      # Hyprland drops a persistent workspace token when the window that first
      # claimed it closes, so Steam's splash takes the token down with it. Learn
      # each token's workspace from its first window and pin later ones there.
      wsPin = pkgs.writeShellScriptBin "hypr-ws-pin" ''
        sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
        declare -A pinned

        while read -r line; do
          case "$line" in
            openwindow'>>'*) ;;
            *) continue ;;
          esac

          addr=''${line#openwindow>>}
          addr=''${addr%%,*}

          read -r pid ws < <(hyprctl -j clients |
            ${pkgs.jq}/bin/jq -r --arg a "0x$addr" \
              '.[] | select(.address==$a) | "\(.pid) \(.workspace.id)"')
          [ -n "''${pid:-}" ] && [ "$pid" -gt 0 ] && [ "''${ws:-0}" -gt 0 ] || continue

          token=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null |
            sed -n 's/^HL_INITIAL_WORKSPACE_TOKEN=//p' | head -1)
          [ -n "$token" ] || continue

          if [ -z "''${pinned[$token]:-}" ]; then
            pinned[$token]=$ws
          elif [ "''${pinned[$token]}" != "$ws" ]; then
            hyprctl dispatch \
              "hl.dsp.window.move({ workspace = ''${pinned[$token]}, follow = false, window = \"address:0x$addr\" })"
          fi
        done < <(${pkgs.socat}/bin/socat -u UNIX-CONNECT:"$sock" -)
      '';
    in
    {
      home.packages = [ wsPin ];
    };
}
