{ config, ... }:
let
  inherit (config.flake.wrappers.hypridle) install;
in
{
  flake.modules.nixos.desktop =
    { config, lib, ... }:
    {
      imports = [ install ];
      wrappers.hypridle.enable = true;

      systemd.user.services.hypridle = {
        description = "hypridle";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        # The lock and DPMS commands come from the session's PATH.
        enableDefaultPath = false;
        serviceConfig = {
          ExecStart = lib.getExe config.wrappers.hypridle.wrapper;
          Restart = "always";
          RestartSec = 10;
        };
      };
    };
}
