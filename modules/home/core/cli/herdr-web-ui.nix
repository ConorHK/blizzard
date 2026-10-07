topLevel: {
  flake.modules.homeManager.herdr-web-ui =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.herdr-web-ui;
      package = topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-web-ui;
    in
    {
      options.programs.herdr-web-ui.settings = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
        example = {
          HERDR_WEB_ALLOWED_ORIGIN = "https://me-herdr.c.tunnels.lab.aws.dev";
        };
        description = "Variables for the plugin env file. Secrets belong in .env.";
      };

      config = {
        # Herdr rewrites plugins.json, so link it.
        home.activation.herdrWebUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run --quiet ${lib.getExe pkgs.herdr} plugin link ${package}/share/herdr-web-ui \
            || warnEcho "herdr plugin link failed for herdr-web-ui"
        '';

        xdg.configFile."herdr/plugins/config/devswha.herdr-web-ui/env" = lib.mkIf (cfg.settings != { }) {
          text = lib.concatLines (lib.mapAttrsToList (name: value: "${name}=${value}") cfg.settings);
        };
      };
    };
}
