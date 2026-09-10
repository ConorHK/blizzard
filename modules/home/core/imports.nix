{ config, ... }:
{
  flake.modules.homeManager.core.imports = with config.flake.modules.homeManager; [
    ai
    direnv
    home-manager
    nh
    nix
    nix-index-database
  ];
}
