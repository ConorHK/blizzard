{ config, ... }:
{
  nixosHosts.dullahan = { };

  homeConfigurations.dullahan = { };

  flake.modules.nixos."nixosConfigurations/dullahan" = {
    imports = with config.flake.modules.nixos; [
      battery
      cachix
      clip
      cnvim
      desktop
      github-nix-access
      home-manager
      intgpu
      nixbuild
      secure-boot
    ];
  };
}
