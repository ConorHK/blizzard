topLevel: {
  flake.modules.nixos.desktop =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      resize = pkgs.writeShellScriptBin "resize" ''
        #!/usr/bin/env bash

        # Initially inspired by https://github.com/exoess

        # Getting some information about the current window
        # windowinfo=$(hyprctl activewindow) removes the newlines and won't work with grep
        hyprctl activewindow > /tmp/windowinfo
        windowinfo=/tmp/windowinfo

        # Run slurp to get position and size
        if ! slurp=$(${pkgs.slurp}/bin/slurp); then
            exit
        fi

        # Parse the output
        pos_x=$(echo $slurp | cut -d " " -f 1 | cut -d , -f 1)
        pos_y=$(echo $slurp | cut -d " " -f 1 | cut -d , -f 2)
        size_x=$(echo $slurp | cut -d " " -f 2 | cut -d x -f 1)
        size_y=$(echo $slurp | cut -d " " -f 2 | cut -d x -f 2)

        # Keep the aspect ratio intact for PiP
        if grep "title: Picture-in-Picture" $windowinfo; then
            old_size=$(grep "size: " $windowinfo | cut -d " " -f 2)
            old_size_x=$(echo $old_size | cut -d , -f 1)
            old_size_y=$(echo $old_size | cut -d , -f 2)
            size_x=$(((old_size_x * size_y + old_size_y / 2) / old_size_y))
            echo $old_size_x $old_size_y $size_x $size_y
        fi

        # Resize and move the (now) floating window
        grep "fullscreen: 1" $windowinfo && hyprctl dispatch fullscreen
        grep "floating: 0" $windowinfo && hyprctl dispatch togglefloating
        hyprctl dispatch moveactive exact $pos_x $pos_y
        hyprctl dispatch resizeactive exact $size_x $size_y
      '';

      screenshot = pkgs.writeShellScriptBin "screenshot" ''
        #!/usr/bin/env bash
        ${lib.getExe pkgs.grimblast} save area - | ${lib.getExe pkgs.satty} --actions-on-escape exit -f -
      '';

      # Firefox titles extension popups only after mapping, past the create-time float rule.
      floatExtensions = pkgs.writeShellScriptBin "float-firefox-extensions" ''
        sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
        ${pkgs.socat}/bin/socat -u UNIX-CONNECT:"$sock" - | while read -r line; do
          case "$line" in
            windowtitlev2">>"*) ;;
            *) continue ;;
          esac
          payload="''${line#windowtitlev2>>}"
          addr="''${payload%%,*}"
          title="''${payload#*,}"
          case "$title" in
            "Extension: "*) ;;
            *) continue ;;
          esac
          state=$(hyprctl -j clients | ${pkgs.jq}/bin/jq -r --arg a "0x$addr" \
            '.[] | select(.address==$a) | "\(.class) \(.floating)"')
          set -- $state
          [ "$1" = "firefox" ] && [ "$2" = "false" ] || continue
          hyprctl dispatch setfloating "address:0x$addr"
          # center on the monitor's usable area; centerwindow races the float
          geo=$(hyprctl -j clients | ${pkgs.jq}/bin/jq -r --arg a "0x$addr" \
            '.[] | select(.address==$a) | "\(.size[0]) \(.size[1]) \(.monitor)"')
          set -- $geo
          w="$1"; h="$2"; mon="$3"
          mgeo=$(hyprctl -j monitors | ${pkgs.jq}/bin/jq -r --argjson id "$mon" \
            '.[] | select(.id==$id) | "\(.x) \(.y) \(.width) \(.height) \(.reserved[0]) \(.reserved[1]) \(.reserved[2]) \(.reserved[3])"')
          set -- $mgeo
          x=$(( $1 + $5 + ($3 - $5 - $7 - w) / 2 ))
          y=$(( $2 + $6 + ($4 - $6 - $8 - h) / 2 ))
          hyprctl dispatch movewindowpixel "exact $x $y,address:0x$addr"
        done
      '';

      base =
        builtins.replaceStrings
          [ "@resize@" "@screenshot@" "@floatExtensions@" ]
          [ (lib.getExe resize) (lib.getExe screenshot) (lib.getExe floatExtensions) ]
          (builtins.readFile ./hypr.lua);

      configText =
        lib.concatStringsSep "\n\n" (
          lib.filter (s: s != "") (
            [
              base
              (topLevel.config.hyprland.perHost.${config.networking.hostName} or "")
            ]
            ++ lib.attrValues topLevel.config.hyprland.lua
          )
        )
        + "\n";

      hyprland =
        (inputs.wrappers.wrapperModules.hyprland.apply {
          "hypr.conf".path = pkgs.writeText "hyprland.lua" configText;
          inherit pkgs;
        }).wrapper;
    in
    {
      programs.hyprland = {
        enable = true;
        package = hyprland;
        withUWSM = true;
        xwayland.enable = true;
      };
      programs.uwsm.enable = true;
      security.pam.services.hyprlock = { };
      users = {
        users.greeter.group = "greeter";
        groups.greeter = { };
      };

      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --remember --cmd '${hyprland}/bin/start-hyprland --path ${lib.getExe hyprland}'";
            user = "greeter";
          };
          initial_session = {
            command = "${hyprland}/bin/start-hyprland --path ${lib.getExe hyprland}";
            user = "goose";
          };
        };
      };
    };
}
