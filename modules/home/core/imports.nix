{ config, inputs, ... }:
{
  flake.modules.homeManager.core.imports = with config.flake.modules.homeManager; [
    home-manager
    nh
    nix
    nix-index-database
    vicinae
  ];
}
