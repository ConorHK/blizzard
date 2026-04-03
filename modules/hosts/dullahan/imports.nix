{ config, ... }:
{
  nixosHosts.dullahan = {
    unstable = true;
  };

  homeConfigurations.dullahan = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/dullahan" = {
    imports = with config.flake.modules.nixos; [
      battery
      intgpu

      cnvim
      cachix

      desktop

      home-manager

      secure-boot
      nixbuild
    ];
  };
}
