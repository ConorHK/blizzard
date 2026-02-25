{
  perSystem =
    { pkgs, ... }:
    {
      packages.wallpapers = import ../../../lib/mkAssetPackage.nix pkgs {
        name = "wallpapers";
        src = ./images;
        glob = "*.png";
        outputDir = "wallpapers";
      };
    };
}
