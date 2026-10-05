topLevel: {
  perSystem =
    { pkgs, ... }:
    {
      packages.pi-advisor = pkgs.runCommand "pi-advisor" { } ''
        cp -r ${./advisor} $out
      '';
    };

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi.advisor;
      settingsFormat = pkgs.formats.json { };
    in
    {
      options.programs.pi.advisor = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the advisor, a reviewer model watching each turn.";
        };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/advisor.json.";
        };
        watchdog = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Advisor-only guidance, installed to ~/.pi/agent/WATCHDOG.md.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi.extensionDirs.advisor =
          topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-advisor;
        home.file =
          lib.optionalAttrs (cfg.settings != { }) {
            ".pi/agent/advisor.json".source = settingsFormat.generate "pi-advisor.json" cfg.settings;
          }
          // lib.optionalAttrs (cfg.watchdog != null) {
            ".pi/agent/WATCHDOG.md".source = cfg.watchdog;
          };
      };
    };
}
