{ config, ... }:
{
  flake.modules.homeManager.core.imports = with config.flake.modules.homeManager; [
    claude
    home-manager
    nh
    nix
    nix-index-database
    syncthing
  ];
}
