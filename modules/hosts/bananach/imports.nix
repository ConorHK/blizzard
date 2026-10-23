{ config, ... }:
{
  flake.tailnetAddresses.bananach = "100.96.40.127";

  nixosHosts.bananach = { };

  flake.modules.nixos."nixosConfigurations/bananach".imports = with config.flake.modules.nixos; [
    server-users
    gatus
    nginx
    github-nix-access
  ];
}
