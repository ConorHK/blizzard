{ config, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [ config.flake.wrappers.hyprlock.install ];
    wrappers.hyprlock.enable = true;
  };
}
