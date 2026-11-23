{ config, ... }:
{
  flake.modules.homeManager.desktop.imports = with config.flake.modules.homeManager; [
    hyprland
    kitty
    media
    social
  ];
}
