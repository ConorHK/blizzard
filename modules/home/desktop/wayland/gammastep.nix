{
  flake.modules.homeManager.gammastep =
    { lib, pkgs, ... }:
    {
      wayland.windowManager.hyprland.settings =
        let
          toggle-gammastep = pkgs.writeShellScriptBin "toggle-gammastep" ''
            #!/usr/bin/env bash

            if systemctl --user is-active --quiet gammastep.service
              then ${lib.getExe pkgs.libnotify} "Stopping gammastep" && systemctl --user stop gammastep.service
              else ${lib.getExe pkgs.libnotify} "Starting gammastep" && systemctl --user start gammastep.service
            fi
          '';
        in
        {
          bind = [
            "SUPER, G, exec, ${lib.getExe toggle-gammastep}"
          ];
        };

      systemd.user.services.gammastep = {
      Install = {
        WantedBy = [ "default.target" ];
      };
      };
      services.gammastep = {
        enable = true;
        provider = "manual";
        latitude = 53.26;
        longitude = 6.15;
        temperature.day = 5500;
        temperature.night = 1900;
        tray = false;
      };
    };
}
