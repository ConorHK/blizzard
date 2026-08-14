{ config, inputs, ... }:
{
  flake.modules.nixos.core.imports = with config.flake.modules.nixos; [
    inputs.disko.nixosModules.disko
    inputs.nixos-facter-modules.nixosModules.facter

    agenix
    determinate-nix
    intrusion
    network
    nix
    root
    security
    substituters
    syncthing
    update
  ];
}
