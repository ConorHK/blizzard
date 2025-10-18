{ lib, ... }:
{
  flake.modules.homeManager.dunst = {
    systemd.user.services.dunst = {
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
    services.dunst = {
      enable = true;
      settings = {
        global = {
          font = lib.mkForce "Monospace";
          offset = "30x50";
          follow = "mouse";
        };
      };
    };
  };
}
