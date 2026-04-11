_: {
  flake.modules.nixos.restic =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.restic;
      inherit (cfg) pauseContainers;

      mkContainerScript =
        action:
        pkgs.writeShellScript "restic-${action}-containers" ''
          ${lib.concatMapStringsSep "\n" (
            c: "XDG_RUNTIME_DIR=/run/user/$(id -u) ${pkgs.systemd}/bin/systemctl --user ${action} ${c}.service"
          ) pauseContainers}
        '';
    in
    {
      options.restic = {
        repository = lib.mkOption {
          type = lib.types.str;
          description = "Restic repository URL.";
        };

        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Paths to include in the backup.";
        };

        pauseContainers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Container services to stop before backup and restart after.";
        };
      };

      config = {
        age.secrets.restic-password = {
          rekeyFile = ./secrets/restic-password.age;
          owner = "containers";
        };

        age.secrets.restic-env = {
          rekeyFile = ./secrets/restic-env.age;
          owner = "containers";
        };

        services.restic.backups.service-data = {
          user = "containers";
          inherit (cfg) repository paths;
          passwordFile = config.age.secrets.restic-password.path;
          environmentFile = config.age.secrets.restic-env.path;
          timerConfig = {
            OnCalendar = "05:45";
            Persistent = true;
          };
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 5"
            "--keep-monthly 12"
            "--keep-yearly 3"
          ];
          extraBackupArgs = [
            "--compression"
            "max"
            "--cleanup-cache"
          ];
          backupPrepareCommand = lib.optionalString (pauseContainers != [ ]) "${mkContainerScript "stop"}";
          backupCleanupCommand = lib.optionalString (pauseContainers != [ ]) "${mkContainerScript "start"}";
        };
      };
    };
}
