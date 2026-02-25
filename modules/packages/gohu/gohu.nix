{
  perSystem =
    { pkgs, ... }:
    {
      packages.gohu = import ../../../lib/mkAssetPackage.nix pkgs {
        name = "gohu-bitmap";
        src = ./fonts;
        glob = "*.bdf";
      };
    };
}
