{ inputs, ... }:
{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # No runtime deps; only pi-bundled peer deps,
      # so the npm tarball needs no npm build.
      pi-zvec-grep = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-zvec-grep";
        version = "0.3.1";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/@luminascale/pi-zvec-grep/-/pi-zvec-grep-${version}.tgz";
          hash = "sha256-V4XBaqnxTc9y+8CMEW8cbBzrmgf8BejnyTceS4nRPSg=";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.zvecGrep.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the zvec-grep extension.";
      };

      config = lib.mkIf config.programs.pi.zvecGrep.enable {
        programs.pi.extensionDirs.zvec-grep = pi-zvec-grep;

        # zg must be on PATH; the extension shells out to it.
        home.packages = [
          (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.zvec-grep
        ];
      };
    };
}
