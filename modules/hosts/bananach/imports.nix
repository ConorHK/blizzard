{ config, ... }:
{
  nixosHosts.bananach = { };

  flake.modules.nixos."nixosConfigurations/bananach".imports = with config.flake.modules.nixos; [
    server-users
    gatus
    nginx
    github-nix-access
  ];
}
