{
  perSystem =
    { pkgs, ... }:
    {
      packages.creeper = import ../../../lib/mkAssetPackage.nix pkgs {
        name = "creeper-bitmap";
        src = ./fonts;
        glob = "*.otb";
      };
    };
}
