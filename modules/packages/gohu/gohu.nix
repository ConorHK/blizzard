{
  perSystem =
    { pkgs, ... }:
    {
      packages.gohu = pkgs.stdenvNoCC.mkDerivation {
        name = "gohu-bitmap";
        version = "1.0";
        src = ./fonts;

        installPhase = ''
          mkdir -p $out/share/fonts
          cp -r $src/*.bdf $out/share/fonts/
        '';
      };
    };
}
