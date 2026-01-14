{ inputs, ... }:
{
  nixosHosts.dullahan = {
    unstable = true;
  };

  flake.modules.nixos."nixosConfigurations/dullahan" = {
    imports = with inputs.self.modules.nixos; [
      battery

      cnvim
      cachix

      desktop

      home-manager

      secure-boot
      nixbuild
    ];

    nixpkgs.overlays = [ inputs.self.overlays.default ];
  };
}
