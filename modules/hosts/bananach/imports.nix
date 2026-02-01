{ inputs, ... }:
{
  nixosHosts.bananach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/bananach".imports = with inputs.self.modules.nixos; [
    fail2ban
    server-users
    uptime-kuma
  ];
}
