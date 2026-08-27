{ config, ... }:
{
  flake.modules.homeManager.core.imports = with config.flake.modules.homeManager; [
    claude
    direnv
    home-manager
    nh
    nix
    nix-index-database
  ];
}
