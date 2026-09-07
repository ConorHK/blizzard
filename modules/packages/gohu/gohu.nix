{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        gohu = import ../../../lib/mkAssetPackage.nix pkgs {
          name = "gohu-bitmap";
          src = ./fonts;
          glob = "*.bdf";
        };

        # Separate family; only kitty gets the lie.
        gohu-otb = pkgs.stdenvNoCC.mkDerivation {
          name = "gohu-otb";
          version = "1.0";
          src = ./fonts;
          nativeBuildInputs = [ pkgs.fontforge ];

          buildPhase = ''
            cat > convert.py <<'PY'
            import fontforge
            f = fontforge.open("gohu.bdf")
            f.familyname = f.fontname = f.fullname = "GohuOTB"
            f.generate("GohuOTB.otb", bitmap_type="otb")
            PY
            fontforge -lang=py -script convert.py
          '';

          installPhase = ''
            install -Dm444 GohuOTB.otb $out/share/fonts/GohuOTB.otb
          '';
        };
      };
    };
}
