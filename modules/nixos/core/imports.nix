{ config, inputs, ... }:
{
  flake.modules.nixos.core.imports = with config.flake.modules.nixos; [
    inputs.disko.nixosModules.disko
    inputs.nixos-facter-modules.nixosModules.facter

    agenix
    alerts
    alerts-secret
    disk-alerts
    determinate-nix
    login-alerts
    network
    nix
    root
    secret-expiry
    security
    storage
    substituters
    syncthing
    update
    zfs-alerts
    zmx
  ];
}
