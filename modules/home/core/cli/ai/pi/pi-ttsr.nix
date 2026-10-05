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
      ruleFiles =
        dir:
        lib.mapAttrs' (file: _: lib.nameValuePair (lib.removeSuffix ".md" file) (dir + "/${file}")) (
          lib.filterAttrs (file: type: type == "regular" && lib.hasSuffix ".md" file) (builtins.readDir dir)
        );
      rules =
        lib.foldl' (acc: dir: acc // ruleFiles dir) { } (lib.filter builtins.pathExists cfg.ruleDirs)
        // cfg.rules;
      settings =
        cfg.settings // lib.optionalAttrs (cfg.rulesSource != null) { inherit (cfg) rulesSource; };
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
        ruleDirs = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = "Directories of global rule files. Later directories win by file name.";
        };
        rules = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Global rule files by name. Wins over ruleDirs.";
        };
        rulesSource = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Checkout directory where /omfg saves global rules.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi = {
          extensionDirs.ttsr = topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-ttsr;
          ttsr = {
            # Consumers' dirs land after this one.
            ruleDirs = lib.mkBefore [ ./ttsr-rules ];
            rulesSource = lib.mkDefault "${config.home.homeDirectory}/repositories/blizzard/modules/home/core/cli/ai/pi/ttsr-rules";
          };
        };
        home.file =
          lib.mapAttrs' (
            name: source: lib.nameValuePair ".pi/agent/rules/${name}.md" { inherit source; }
          ) rules
          // lib.optionalAttrs (settings != { }) {
            ".pi/agent/ttsr.json".source = settingsFormat.generate "pi-ttsr.json" settings;
          };
      };
    };
}
