{
  flake.modules.wrapper."hyprland/rules" =
    { config, ... }:
    let
      inherit (config) pkgs;
      # Firefox titles extension popups after mapping, so the create-time float
      # rule misses them; float+center them when the title actually arrives.
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
    in
    {
      settings = {
        windowrule = [
          # Float and center file pickers
          "float on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
          "center on, match:class xdg-desktop-portal-gtk, match:title ^(Open.*Files?|Save.*Files?|All Files|Save)"
          "float on, match:title ^(File Upload)"
          "center on, match:title ^(File Upload)"

          # Firefox extension popups (Bitwarden, etc.) float via
          # float-firefox-extensions below; Picture-in-Picture is born titled so
          # a plain rule works for it.
          "float on, match:class ^(firefox)$, match:title ^(Picture-in-Picture)$"

          # Float only the Steam Friends List; let the main window tile
          "float on, match:class ^(steam)$, match:initial_title ^(Friends List)$"
          "float on, match:class com.saivert.pwvucontrol"
          "center on, match:class com.saivert.pwvucontrol"
        ];
        exec-once = [
          "${floatExtensions}/bin/float-firefox-extensions"
        ];
      };
    };
}
