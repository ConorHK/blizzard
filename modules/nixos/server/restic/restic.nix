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
          restic-password.rekeyFile = ./secrets/restic-password.age;
          restic-env.rekeyFile = ./secrets/restic-env.age;
          restic-ntfy-topic.rekeyFile = ./secrets/restic-ntfy-topic.age;
        };

        systemd.services.restic-backups-service-data.unitConfig.OnFailure =
          "restic-backups-notify-failure.service";

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
