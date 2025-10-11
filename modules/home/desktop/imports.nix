{ config, ... }:
{
  flake.modules.homeManager.desktop.imports = with config.flake.modules.homeManager; [
    media
    social
    hyprland
    firefox
    alacritty
  ];
}
