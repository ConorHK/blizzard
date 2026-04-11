{ config, ... }:
{
  nixosHosts.bananach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/bananach".imports = with config.flake.modules.nixos; [
    server-users
    gatus
    github-nix-access
  ];
}
