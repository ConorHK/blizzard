{ config, ... }:
{
  nixosHosts.abhartach = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/abhartach" = {
    imports = with config.flake.modules.nixos; [
      amdgpu

      beeper

      cnvim
      cachix

      desktop
      gaming

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
