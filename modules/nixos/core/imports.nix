{ config, inputs, ... }:
{
  flake.modules.nixos.core.imports = with config.flake.modules.nixos; [
    inputs.disko.nixosModules.disko
    inputs.nixos-facter-modules.nixosModules.facter

    agenix
    alerts
    alerts-secret
    determinate-nix
    login-alerts
    network
    nix
    root
    security
    substituters
    syncthing
    update
  ];
}
