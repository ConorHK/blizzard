{ config, ... }:
let
  inherit (config.flake.wrappers.waybar) install;
in
{
  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ install ];
      wrappers.waybar.enable = true;

      systemd.user.services.waybar = {
        description = "Highly customizable Wayland bar for Sway and Wlroots based compositors.";
        documentation = [ "https://github.com/Alexays/Waybar/wiki" ];
        after = [ "graphical-session.target" ];
        partOf = [
          "tray.target"
          "graphical-session.target"
        ];
        wantedBy = [
          "tray.target"
          "graphical-session.target"
        ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        # The bar's click commands come from the session's PATH.
        enableDefaultPath = false;
        serviceConfig = {
          ExecStart = lib.getExe config.wrappers.waybar.wrapper;
          ExecReload = "${pkgs.coreutils}/bin/kill -SIGUSR2 $MAINPID";
          KillMode = "mixed";
          Restart = "on-failure";
        };
      };
    };
}
