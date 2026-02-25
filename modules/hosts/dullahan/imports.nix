{ config, ... }:
{
  nixosHosts.dullahan = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/dullahan" = {
    imports = with config.flake.modules.nixos; [
      battery

      cnvim
      cachix

      desktop

      home-manager

      secure-boot
      nixbuild
    ];

    nixpkgs.overlays = [ config.flake.overlays.default ];
  };
}
