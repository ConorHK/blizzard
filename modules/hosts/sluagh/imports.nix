{ config, ... }:
{
  nixosHosts.sluagh = { };

  # Kept from the Debian install's tailscale state.
  flake.tailnetAddresses.sluagh = "100.66.244.36";

  flake.modules.nixos."nixosConfigurations/sluagh".imports = with config.flake.modules.nixos; [
    docker
    server-users
    systemd-boot
  ];
}
