{ config, ... }:
{
  nixosHosts.sluagh = { };

  flake.modules.nixos."nixosConfigurations/sluagh".imports = with config.flake.modules.nixos; [
    server-users
    systemd-boot
  ];
}
