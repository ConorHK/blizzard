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
        age.secrets = {
          restic-password = {
            rekeyFile = ./secrets/restic-password.age;
            owner = "containers";
          };

          restic-env = {
            rekeyFile = ./secrets/restic-env.age;
            owner = "containers";
          };
          restic-ntfy-topic.rekeyFile = ./secrets/restic-ntfy-topic.age;
        };

        systemd.services.restic-backups-service-data = {
          unitConfig.OnFailure = "restic-backups-notify-failure.service";
          # Yield CPU during the run; ZFS ignores ionice, so no I/O class here
          serviceConfig.Nice = 19;
        };

        systemd.services.restic-backups-notify-failure = {
          description = "Notify restic backup failure via ntfy";
          serviceConfig = {
            Type = "oneshot";
            EnvironmentFile = config.age.secrets.restic-ntfy-topic.path;
          };
          script = ''
            ${pkgs.curl}/bin/curl -fsS https://ntfy.sh \
              -H "Content-Type: application/json" \
              -d "{\"topic\": \"$NTFY_TOPIC\", \"title\": \"Backup failed on ${config.networking.hostName}\", \"message\": \"restic backup service-data failed — check journalctl -u restic-backups-service-data\", \"priority\": 4, \"tags\": [\"warning\"]}"
          '';
        };

        services.restic.backups.service-data = {
          user = "containers";
          inherit (cfg) repository paths;
          passwordFile = config.age.secrets.restic-password.path;
          environmentFile = config.age.secrets.restic-env.path;
          # Keep well clear of the 06:00-07:00 autoUpgrade reboot window: a
          # reboot mid-backup leaves a stale repo lock and the interrupted unit
          # is "stopped", not "failed", so OnFailure would never alert about it.
          timerConfig = {
            OnCalendar = "03:00";
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
            "auto"
            "--cleanup-cache"
            # One reader at a time; spinning ZFS pool seeks poorly under parallel reads
            "--read-concurrency"
            "1"
          ];
          # `restic unlock` clears stale locks left by an interrupted run;
          # otherwise every later backup fails silently on the lock.
          backupPrepareCommand = ''
            ${pkgs.restic}/bin/restic unlock
            ${lib.optionalString (pauseContainers != [ ]) (mkContainerScript "stop")}
          '';
          backupCleanupCommand = lib.optionalString (pauseContainers != [ ]) "${mkContainerScript "start"}";
        };
      };
    };
}
