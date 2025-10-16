{ lib, ... }:
{
  flake.modules.homeManager.dunst = {
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
