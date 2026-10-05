topLevel: {
  perSystem =
    { pkgs, ... }:
    {
      packages.pi-ttsr = pkgs.stdenvNoCC.mkDerivation {
        pname = "pi-ttsr";
        version = "0.1.0";
        src = ./ttsr;
        picomatch = pkgs.fetchurl {
          url = "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz";
          hash = "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/node_modules/picomatch
          cp -r . $out
          tar xzf $picomatch -C $out/node_modules/picomatch --strip-components=1
          substituteInPlace $out/index.ts \
            --replace-fail '@astGrep@' '${pkgs.lib.getExe pkgs.ast-grep}'
          runHook postInstall
        '';
      };
    };

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi.ttsr;
      settingsFormat = pkgs.formats.json { };
    in
    {
      options.programs.pi.ttsr = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the TTSR extension with /omfg.";
        };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/ttsr.json.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi.extensionDirs.ttsr =
          topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-ttsr;
        home.file.".pi/agent/ttsr.json" = lib.mkIf (cfg.settings != { }) {
          source = settingsFormat.generate "pi-ttsr.json" cfg.settings;
        };
      };
    };
}
