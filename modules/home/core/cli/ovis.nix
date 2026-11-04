topLevel: {
  flake.modules.homeManager.ovis =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ovis;
      inherit (topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) ovis herdr-core;
    in
    {
      options.programs.ovis = {
        runtime = lib.mkOption {
          type = lib.types.enum [
            "herdr"
            "herdr-core"
          ];
          default = "herdr";
          description = ''
            Terminals Ovis shows. `herdr` runs it as a plugin of herdr's TUI
            server; `herdr-core` runs it as a user service beside herdr-core.
          '';
        };

        settings = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
          example = {
            OVIS_ALLOWED_ORIGIN = "https://ovis.example.com";
          };
          description = ''
            Server environment variables, readable in the Nix store. Put secrets
            such as OVIS_TOKEN in the plugin .env, or in ~/.config/ovis/env
            (mode 600) for herdr-core.
          '';
        };
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.runtime == "herdr") {
          # Herdr rewrites plugins.json, so link it.
          home.activation.ovis = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run --quiet ${lib.getExe pkgs.herdr} plugin link ${ovis}/share/ovis \
              || warnEcho "herdr plugin link failed for ovis"
          '';

          xdg.configFile."herdr/plugins/config/devswha.ovis/env" = lib.mkIf (cfg.settings != { }) {
            text = lib.concatLines (lib.mapAttrsToList (name: value: "${name}=${value}") cfg.settings);
          };
        })

        (lib.mkIf (cfg.runtime == "herdr-core") {
          programs.ovis.settings = {
            OVIS_RUNTIME = "herdr-core";
            OVIS_HC_BIN = lib.mkDefault (lib.getExe' herdr-core "hc");
            # The new-agent picker lists only agents on this PATH.
            PATH = lib.mkDefault "${config.home.profileDirectory}/bin:${config.home.homeDirectory}/.local/bin:/usr/local/bin:/usr/bin:/bin";
          };

          systemd.user.services.ovis = {
            Unit.Description = "Ovis web client for herdr-core";
            Service = {
              ExecStart = "${lib.getExe' ovis "ovis-bun"} ${ovis}/share/ovis/server/managed.ts";
              Environment = lib.mapAttrsToList (name: value: "${name}=${value}") cfg.settings;
              EnvironmentFile = "-${config.xdg.configHome}/ovis/env";
              Restart = "on-failure";
              RestartSec = 5;
              # hc may start herdr-core inside this unit, and it must outlive Ovis.
              KillMode = "process";
            };
            Install.WantedBy = [ "default.target" ];
          };
        })
      ];
    };
}
