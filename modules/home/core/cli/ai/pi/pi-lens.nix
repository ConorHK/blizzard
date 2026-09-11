{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Vendored: pi never npm-installs local packages.
      # Hashes are the registry sha512 integrity values.
      deps = {
        "js-yaml" = {
          version = "5.4.1";
          hash = "sha512-28R/k+NAjeuf7+CKlTxWZVExJGwVVLwY06DgEnOMz2gEpfNkDcD7QvyiVPT0xy0XXhU8vHsd4Ot42OOPdJG7dQ==";
        };
        "argparse" = {
          version = "2.0.1";
          hash = "sha512-8+9WqebbFzpX9OR+Wa6O29asIogeRMzcGtAINdpMHHyAg10f05aSFVBbcEqGf/PXw1EjAZ+q2/bEBg3DvurK3Q==";
        };
        "pidusage" = {
          version = "4.0.1";
          hash = "sha512-yCH2dtLHfEBnzlHUJymR/Z1nN2ePG3m392Mv8TFlTP1B0xkpMQNHAnfkY0n2tAi6ceKO6YWhxYfZ96V4vVkh/g==";
        };
        "safe-buffer" = {
          version = "5.2.1";
          hash = "sha512-rp3So07KcdmmKbGvgaNxQSJr7bGVSVk5S9Eq1F+ppbRo70+YeaDxkw5Dd8NPN+GD6bjnYm2VuPuCXmpuYvmCXQ==";
        };
        "minimatch" = {
          version = "10.2.6";
          hash = "sha512-vpLQEs+VLCr1nU0BXS07maYoFwlDAH0gngQuuttxIwutDFEMHq2blX+8vpgxDdK3J1PwjCJiep77OitTZ4Ll1A==";
        };
        "brace-expansion" = {
          version = "5.0.9";
          hash = "sha512-ScQ4IuvIEF1TMlP7Zt+vjJ//9zlPb2SDcxWxM3bk8s6t6GGdJ7KO1dCcTidOPJKePW30LE/2cT7wCyPho9/Wxg==";
        };
        "balanced-match" = {
          version = "4.0.4";
          hash = "sha512-BLrgEcRTwX2o6gGxGOCNyMvGSp35YofuYzw9h1IMTRmKqttAZZVU67bdb9Pr2vUHA8+j3i2tJfjO6C6+4myGTA==";
        };
        "vscode-jsonrpc" = {
          version = "9.0.2";
          hash = "sha512-SbQSV9yRemARxeXw6LU5sS6Zq0e9/DgCCX5yelH263ZQWukbTk8EF8fjTrr1dziasf4GwlJbvTwFnTrnQFWZXQ==";
        };
        "detect-libc" = {
          version = "2.1.2";
          hash = "sha512-Btj2BOOO83o3WyH59e8MgXsxEQVcarkUOpEYrubB0urwnN10yQ364rsiByU11nZlqWYZm05i/of7io4mzihBtQ==";
        };
        "@ast-grep/napi" = {
          version = "0.45.3";
          hash = "sha512-bjJsUt0g3UCwbn9bjv7MnoR15rszSm79yPCXn4DWWK0NuYUUqBU/srtNMR4WnpfR7TnfBRdYFoqSNx0pGCNWJg==";
        };
        "@ast-grep/napi-linux-x64-gnu" = {
          version = "0.45.3";
          hash = "sha512-lluRK3hxfHMQdFuVID6seAKVx4FH0kEwF6rCh5/I40Sf3EtNR2UCBXAqd6RBA6hqlSckktvBxCfw+h4aescDmg==";
        };
        "@ast-grep/cli" = {
          version = "0.45.3";
          hash = "sha512-Cm07SHb8Q8dJfAQhrPOveAGuuzznmf6IjQa2+0Yvjt8Qfo+XIVbEIo0Prng+UDVMlaCS/FkF2eA8M3F6z4+0Wg==";
        };
      };
      tarball =
        name: dep:
        pkgs.fetchurl {
          url = "https://registry.npmjs.org/${name}/-/${lib.last (lib.splitString "/" name)}-${dep.version}.tgz";
          inherit (dep) hash;
        };
      unpackDeps = lib.concatStrings (
        lib.mapAttrsToList (name: dep: ''
          mkdir -p $out/node_modules/${name}
          tar xzf ${tarball name dep} -C $out/node_modules/${name} --strip-components=1
        '') deps
      );
      pi-lens = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-lens";
        version = "4.1.6";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-lens/-/pi-lens-${version}.tgz";
          hash = "sha512-PnVCEumGiMOUQ6t6zvr2EJl+r6IhALYwuReufQ1FUHKrSNoCsdb/dUws1l2U0nPRKibgJlaJFM4uM46TDrafNA==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
          ${unpackDeps}
          # What @ast-grep/cli's postinstall does, with the
          # nixpkgs binary: npm's needs glibc 2.34.
          mkdir -p $out/node_modules/.bin
          for bin in ast-grep sg; do
            ln -sf ${lib.getExe pkgs.ast-grep} $out/node_modules/@ast-grep/cli/$bin
            ln -s ../@ast-grep/cli/$bin $out/node_modules/.bin/$bin
          done
          runHook postInstall
        '';
        meta.platforms = [ "x86_64-linux" ];
      };
    in
    {
      options.programs.pi.lens = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the pi-lens package.";
        };
        tools = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ pkgs.ast-grep ];
          description = "Language tools pi-lens resolves from PATH.";
        };
      };

      config = lib.mkIf config.programs.pi.lens.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-lens}" ];

        # Tools come from PATH only, never runtime installs.
        programs.pi.env.PI_LENS_DISABLE_TOOL_INSTALL = "1";
        home.packages = config.programs.pi.lens.tools;
      };
    };
}
