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
      cachix
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
