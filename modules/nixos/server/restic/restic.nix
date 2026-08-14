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

        passwordFile = lib.mkOption {
          type = lib.types.path;
          description = "File containing the repository password.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Environment file holding repository backend credentials.";
        };

        ntfyTopicFile = lib.mkOption {
          type = lib.types.path;
          description = "File sourced for the NTFY_TOPIC backup alerts go to.";
        };
      };

      config = {
        systemd = {
          services = {
            restic-backups-service-data = {
              unitConfig.OnFailure = "restic-backups-notify-failure.service";
              # Yield CPU during the run; ZFS ignores ionice, so no I/O class here
              serviceConfig.Nice = 19;
            };

            restic-backups-notify-failure = {
              description = "Notify restic backup failure via ntfy";
              serviceConfig = {
                Type = "oneshot";
                Environment = "ALERT_TOPIC_FILE=${cfg.ntfyTopicFile}";
                ExecStart = "${lib.getExe config.blizzard.alerts.send} 'Backup failed' 'restic backup service-data failed — check journalctl -u restic-backups-service-data' 4 warning";
              };
            };

            restic-backups-freshness = {
              description = "Alert if the newest restic snapshot is stale";
              # The watchdog itself must not fail silently.
              unitConfig.OnFailure = "alert-failure@restic-backups-freshness.service";
              # Root, not the `containers` backup user: the ntfy topic is root-owned.
              serviceConfig = {
                Type = "oneshot";
                EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
                # Units get no $HOME, and restic refuses to run without a cache
                # location — without this it fails before it can ever report.
                CacheDirectory = "restic-freshness";
                CacheDirectoryMode = "0700";
                Environment = [
                  "RESTIC_REPOSITORY=${cfg.repository}"
                  "RESTIC_PASSWORD_FILE=${cfg.passwordFile}"
                  "RESTIC_CACHE_DIR=%C/restic-freshness"
                  "ALERT_TOPIC_FILE=${cfg.ntfyTopicFile}"
                ];
              };
              script = ''
                set -uo pipefail
                alert() {
                  ${lib.getExe config.blizzard.alerts.send} "Backup stale" "$1" 4 warning
                }
                # `|| true`: the generated job script runs with -e, so an
                # unreachable or uninitialized repo would abort before alerting.
                # restic's stderr goes to the journal, not /dev/null, so the
                # reason an alert fired is recoverable afterwards.
                newest=$(${pkgs.restic}/bin/restic snapshots --json --latest 1 \
                  | ${pkgs.jq}/bin/jq -r 'max_by(.time).time // empty' || true)
                if [ -z "$newest" ]; then
                  alert "restic reports no snapshots (repo unreachable or empty) — check journalctl -u restic-backups-service-data"
                  exit 0
                fi
                age=$(( $(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/date -d "$newest" +%s) ))
                # 26h: one daily backup plus margin for a slow run.
                if [ "$age" -gt 93600 ]; then
                  alert "newest snapshot is $((age / 3600))h old — backup has not run"
                fi
              '';
            };
          };

          # Dead-man's switch: OnFailure only fires when a run *fails*. A timer that
          # never triggers (host off at 03:00, systemd wedged) produces no backup and
          # no alert. This checks the repo's newest snapshot age daily and pages if
          # it's stale — catching silent non-runs and empty backups alike. Reads the
          # real repo, so it also verifies the backup exists, not just that a unit ran.
          timers.restic-backups-freshness = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "10:00";
              Persistent = true;
            };
          };
        };

        services.restic.backups.service-data = {
          user = "containers";
          inherit (cfg)
            repository
            paths
            passwordFile
            environmentFile
            ;
          # Create the repo on first run instead of failing. Idempotent, and the
          # difference between a working DR restore and a silent failure at the
          # worst possible time if the B2 bucket ever has to be recreated.
          initialize = true;
          # An unverified backup is a hope, not a backup. `restic check` validates
          # repo structure every run; --read-data-subset reads and re-hashes a
          # rotating 2.5% of pack files so the whole repo's *data* is verified over
          # ~40 days without the I/O cost of reading it all nightly.
          checkOpts = [ "--read-data-subset=2.5%" ];
          # Emit progress to the journal; restic is otherwise silent without a TTY
          progressFps = 0.1;
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
