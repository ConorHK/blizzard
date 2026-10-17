{ config, ... }:
{
  flake.modules.homeManager.core.imports = with config.flake.modules.homeManager; [
    ai
    home-manager
    nh
    nix
    nix-index-database
  ];
}
