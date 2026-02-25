{
  flake.modules.nixos."nixosConfigurations/dullahan" = import ../../../lib/mkDisko.nix { };
}
