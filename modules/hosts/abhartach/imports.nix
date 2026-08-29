{ config, ... }:
{
  nixosHosts.abhartach = { };

  homeConfigurations.abhartach = { };

  flake.modules.nixos."nixosConfigurations/abhartach" = {
    imports = with config.flake.modules.nixos; [
      amdgpu
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
      secure-boot
      sunshine
      virtualization
    ];
  };
}
