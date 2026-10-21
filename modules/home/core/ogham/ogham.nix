{
  flake.modules.homeManager.ogham =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.ogham;
      vault = "${config.home.homeDirectory}/ogham";

      cli = pkgs.writeShellApplication {
        name = "ogham";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.flock
          pkgs.git
          pkgs.gnugrep
          # Activation PATH has no ssh.
          pkgs.openssh
        ];
        text = builtins.readFile ./ogham.sh;
      };
    in
    {
      options.programs.ogham = {
        enable = lib.mkEnableOption "the ogham notes repo in ~/ogham";

        remote = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "ssh://git.example.com/notes";
          description = "Git hub the repo clones from and syncs with.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default = cli;
          readOnly = true;
          description = "The ogham CLI.";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ cli ];

        home.activation.ogham = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run ${lib.getExe cli} init ${vault} ${lib.escapeShellArg (toString cfg.remote)}
        '';

        systemd.user = {
          services.ogham-sync = {
            Unit.Description = "Commit and sync the ogham repo";
            Service = {
              Type = "oneshot";
              ExecStart = "${lib.getExe cli} sync ${vault}";
            };
          };
          timers.ogham-sync = {
            Unit.Description = "Sync the ogham repo every 5 minutes";
            Timer = {
              OnCalendar = "*:0/5";
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
