{ config, ... }:
{
  nixosHosts.sluagh = { };

  flake.modules.nixos."nixosConfigurations/sluagh".imports = with config.flake.modules.nixos; [
    ci-runner
    home-manager
    server-users
    systemd-boot
    users
    wake-abhartach
  ];
}
