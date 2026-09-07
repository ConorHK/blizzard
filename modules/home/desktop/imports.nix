{ config, ... }:
{
  flake.modules.homeManager.desktop.imports = with config.flake.modules.homeManager; [
    alacritty
    firefox
    hyprland
    kitty
    media
    network-manager
    social
    vicinae
  ];
}
