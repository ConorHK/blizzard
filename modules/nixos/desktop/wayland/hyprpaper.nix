{ config, ... }:
let
  inherit (config.flake.wrappers.hyprpaper) install;
in
{
  flake.modules.nixos.desktop =
    { config, lib, ... }:
    {
      imports = [ install ];
      wrappers.hyprpaper.enable = true;

      systemd.user.services.hyprpaper = {
        description = "hyprpaper";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        enableDefaultPath = false;
        serviceConfig = {
          ExecStart = lib.getExe config.wrappers.hyprpaper.wrapper;
          Restart = "always";
          RestartSec = 10;
        };
      };
    };
}
