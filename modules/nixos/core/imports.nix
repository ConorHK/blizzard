{ config, inputs, ... }:
{
  flake.modules.nixos.core.imports = with config.flake.modules.nixos; [
    inputs.disko.nixosModules.disko
    inputs.nixos-facter-modules.nixosModules.facter

    agenix
    github-nix-access
    network
    nix
    root
    security
    substituters
    syncthing
    update
  ];
}
