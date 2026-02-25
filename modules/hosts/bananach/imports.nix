{ config, ... }:
{
  nixosHosts.bananach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/bananach".imports = with config.flake.modules.nixos; [
    fail2ban
    server-users
    uptime-kuma
  ];
}
