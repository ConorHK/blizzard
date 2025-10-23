{ config, ... }:
{
  flake.modules.homeManager.desktop.imports = with config.flake.modules.homeManager; [
    alacritty
    firefox
    hyprland
    media
    network-manager
    social
    vicinae
  ];
}
