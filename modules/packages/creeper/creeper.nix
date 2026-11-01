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

        # fontdb loads only .otf and needs a PostScript name, which the .otb files lack.
        creeper-otf = pkgs.stdenvNoCC.mkDerivation {
          name = "creeper-otf";
          version = "1.0";
          src = ./fonts;
          nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.fonttools ])) ];

          buildPhase = ''
            python3 -I ${./psname.py} creeper8x15r.otb creeper8x15r.otf creeper-Regular
            python3 -I ${./psname.py} creeper8x15b.otb creeper8x15b.otf creeper-Bold
          '';

          installPhase = ''
            install -Dm444 -t $out/share/fonts/opentype creeper8x15r.otf creeper8x15b.otf
          '';
        };
      };
    };
}
