{ config, ... }:
{
  nixosHosts.abhartach = { };

  homeConfigurations.abhartach = { };

  flake.modules.nixos."nixosConfigurations/abhartach" = {
    imports = with config.flake.modules.nixos; [
      amdgpu
      backup
      backup-b2
      backup-home
      backup-secrets
      beeper
      bitbang
      cachix
      clip
      cnvim
      desktop
      gaming
      github-nix-access
      home-manager
      kubernetes
      kvm-amd
      nixbuild
      pi
      secure-boot
      sunshine
      virtualization
    ];
  };
}
