{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        creeper = import ../../../lib/mkAssetPackage.nix pkgs {
          name = "creeper-bitmap";
          src = ./fonts;
          glob = "*.otb";
        };

        # The 15px bitmaps as .otf, which fontdb loads, with whole-pixel metrics.
        creeper-otf = pkgs.stdenvNoCC.mkDerivation {
          name = "creeper-otf";
          version = "1.0";
          src = ./fonts;
          nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ];

          buildPhase = ''
            python3 -I ${./fix-metrics.py} creeper8x15r.otb creeper-regular.otf creeper-Regular
            python3 -I ${./fix-metrics.py} creeper8x15b.otb creeper-bold.otf creeper-Bold
          '';

          installPhase = ''
            install -Dm444 -t $out/share/fonts/opentype creeper-regular.otf creeper-bold.otf
          '';
        };
      };
    };
}
