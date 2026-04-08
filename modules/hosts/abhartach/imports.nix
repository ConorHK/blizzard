{ config, ... }:
{
  nixosHosts.abhartach = {
    unstable = true;
  };

  homeConfigurations.abhartach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/abhartach" = {
    imports = with config.flake.modules.nixos; [
      amdgpu
      beeper
      cachix
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
