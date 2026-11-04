{
  perSystem =
    { pkgs, self', ... }:
    {
      packages = {
        creeper = import ../../../lib/mkAssetPackage.nix pkgs {
          name = "creeper-bitmap";
          src = ./fonts;
          glob = "*.otb";
        };

        # The 15px bitmaps as .otf, which fontdb loads, with whole-pixel metrics.
        # Unifont fills the symbols and emoji creeper lacks, so none fall back.
        creeper-otf = pkgs.stdenvNoCC.mkDerivation {
          name = "creeper-otf";
          version = "1.0";
          src = ./fonts;
          nativeBuildInputs = [
            (pkgs.python3.withPackages (p: [
              p.fontforge
              p.fonttools
            ]))
          ];

          buildPhase = ''
            tar xzf ${pkgs.unifont.src} --wildcards --strip-components 3 '*/precompiled/unifont-*.hex' '*/precompiled/unifont_upper-*.hex'
            for style in r:Regular b:Bold; do
              s=''${style%:*} name=''${style#*:}
              python3 -I ${./add-unifont.py} misc/creeper8x15$s.bdf creeper8x15$s.otb merged-$s.otb unifont-*.hex unifont_upper-*.hex
              python3 -I ${./fix-metrics.py} merged-$s.otb creeper-''${name,,}.otf creeper-$name
            done
          '';

          installPhase = ''
            install -Dm444 -t $out/share/fonts/opentype creeper-regular.otf creeper-bold.otf
          '';
        };

        # macOS draws no bitmap-only fonts, so trace the strike to outlines.
        creeper-ttf =
          pkgs.runCommand "creeper-ttf"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (p: [
                  p.fonttools
                  p.skia-pathops
                ]))
              ];
            }
            ''
              dir=$out/share/fonts/truetype
              mkdir -p $dir
              for style in regular bold; do
                python3 -I ${./outline.py} \
                  ${self'.packages.creeper-otf}/share/fonts/opentype/creeper-$style.otf $dir/creeper-$style.ttf
              done
            '';
      };
    };
}
