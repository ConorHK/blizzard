{
  # Not wired into the hyprland config; the gammastep module is unused.
  flake.modules.wrapper."hyprland/gammastep" =
    { config, lib, ... }:
    {
      settings.bind =
        let
          inherit (config) pkgs;
          toggle-gammastep = pkgs.writeShellScriptBin "toggle-gammastep" ''
            #!/usr/bin/env bash

            if systemctl --user is-active --quiet gammastep.service
              then ${lib.getExe pkgs.libnotify} "Stopping gammastep" && systemctl --user stop gammastep.service
              else ${lib.getExe pkgs.libnotify} "Starting gammastep" && systemctl --user start gammastep.service
            fi
          '';
        in
        [
          "SUPER, G, exec, ${lib.getExe toggle-gammastep}"
        ];
    };

  flake.modules.homeManager.gammastep = {
    systemd.user.services.gammastep = {
      Install = {
        WantedBy = [ "graphical-session.target" ];
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
