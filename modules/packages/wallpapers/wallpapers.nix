{
  perSystem =
    { pkgs, ... }:
    {
      packages.wallpapers = pkgs.stdenvNoCC.mkDerivation {
        name = "wallpapers";
        version = "1.0";
        src = ./images;

        installPhase = ''
          mkdir -p $out/wallpapers/
          cp -r $src/*.png $out/wallpapers/
        '';
      };
    };
}
