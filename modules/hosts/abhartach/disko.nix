{
  flake.modules.nixos."nixosConfigurations/abhartach" = import ../../../lib/mkDisko.nix {
    fido2 = true;
  };
}
