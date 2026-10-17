{
  hyprland.lua.workspacePin = ''
    hl.on("hyprland.start", function()
      hl.exec_cmd("hypr-ws-pin")
    end)
  '';

  flake.modules.homeManager.hypr-workspace-pin =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.programs.hypr-ws-pin) exempt;

      # Hyprland drops a persistent workspace token when the window that first
      # claimed it closes, so Steam's splash takes the token down with it. Learn
      # each token's workspace from its first window and pin later ones there.
      # Manual moves retarget the pin so herding follows the user.
      wsPin = pkgs.writeShellScriptBin "hypr-ws-pin" ''
        sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
        declare -A pinned
        declare -A owner

        while read -r line; do
          case "$line" in
            openwindow'>>'*)
              addr=''${line#openwindow>>}
              addr=''${addr%%,*}

              read -r pid ws class < <(hyprctl -j clients |
                ${pkgs.jq}/bin/jq -r --arg a "0x$addr" \
                  '.[] | select(.address==$a) | "\(.pid) \(.workspace.id) \(.class)"')
              [ -n "''${pid:-}" ] && [ "$pid" -gt 0 ] && [ "''${ws:-0}" -gt 0 ] || continue
              ${lib.optionalString (exempt != [ ]) ''
                case "$class" in
                  ${lib.concatMapStringsSep "|" lib.escapeShellArg exempt}) continue ;;
                esac
              ''}

              token=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null |
                sed -n 's/^HL_INITIAL_WORKSPACE_TOKEN=//p' | head -1)
              [ -n "$token" ] || continue
              owner[$addr]=$token

              if [ -z "''${pinned[$token]:-}" ]; then
                pinned[$token]=$ws
              elif [ "''${pinned[$token]}" != "$ws" ]; then
                hyprctl dispatch \
                  "hl.dsp.window.move({ workspace = ''${pinned[$token]}, follow = false, window = \"address:0x$addr\" })"
              fi
              ;;
            movewindow'>>'*)
              addr=''${line#movewindow>>}
              addr=''${addr%%,*}
              [ -n "''${owner[$addr]:-}" ] || continue

              ws=$(hyprctl -j clients |
                ${pkgs.jq}/bin/jq -r --arg a "0x$addr" \
                  '.[] | select(.address==$a) | .workspace.id')
              # special workspaces have negative ids; ignore them
              [ "''${ws:-0}" -gt 0 ] && pinned[''${owner[$addr]}]=$ws
              ;;
            closewindow'>>'*)
              addr=''${line#closewindow>>}
              unset "owner[$addr]"
              ;;
          esac
        done < <(${pkgs.socat}/bin/socat -u UNIX-CONNECT:"$sock" -)
      '';
    in
    {
      options.programs.hypr-ws-pin.exempt = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Window classes to leave unpinned. Single-instance apps reuse their first token for every window.";
      };

      config.home.packages = [ wsPin ];
    };
}
