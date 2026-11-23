{ config, ... }:
{
  flake.modules.homeManager.desktop.imports = with config.flake.modules.homeManager; [
    firefox
    hyprland
    kitty
    media
    social
  ];
}
