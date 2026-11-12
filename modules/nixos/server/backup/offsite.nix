_: {
  # A USB drive kept off site; plugging it in backs up service-data to it.
  flake.modules.nixos.backup-offsite =
    { config, lib, ... }:
    let
      cfg = config.blizzard.backup.offsite;
      source = config.blizzard.backup.jobs.service-data;
      mountPoint = "/mnt/offsite";
      mountUnit = "mnt-offsite.mount";
      alertSend = lib.getExe config.blizzard.alerts.send;
      statusFile = "/var/lib/restic-status/offsite.backup";
    in
    {
      options.blizzard.backup.offsite = {
        label = lib.mkOption {
          type = lib.types.str;
          default = "offsite";
          description = "Filesystem label of the offsite drive.";
        };

        maxAgeDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = "Days without an offsite run before alerting.";
        };
      };

      config = {
        fileSystems.${mountPoint} = {
          device = "/dev/disk/by-label/${cfg.label}";
          fsType = "ext4";
          # Absent most of the time; boot must not wait for it.
          options = [
            "noauto"
            "nofail"
            "noatime"
          ];
        };

        blizzard.backup.jobs.offsite = {
          inherit (source)
            user
            paths
            dumpPaths
            exclude
            zfsDatasets
            pauseContainers
            passwordFile
            ;
          repository = "${mountPoint}/restic";
          environmentFile = null;
          # Runs on plug-in, not on a clock.
          schedule = null;
          drillSchedule = null;
          freshness = false;
        };

        services.udev.extraRules = ''
          ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${cfg.label}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="offsite-backup.service"
        '';

        systemd = {
          services = {
            restic-backups-offsite.unitConfig.RequiresMountsFor = mountPoint;

            offsite-backup = {
              description = "Back up to the offsite drive, then unmount it";
              unitConfig.OnFailure = "alert-failure@offsite-backup.service";
              serviceConfig = {
                Type = "oneshot";
                Environment = "ALERT_TOPIC_FILE=${config.blizzard.backup.ntfyTopicFile}";
              };
              script = ''
                set -euo pipefail
                ${alertSend} "Offsite backup started" "Leave the drive plugged in" 3 floppy_disk
                systemctl start ${mountUnit}
                install -d -o ${source.user} -g ${source.user} -m 0700 ${mountPoint}/restic
                trap 'systemctl stop ${mountUnit}' EXIT
                systemctl start restic-backups-offsite.service
                systemctl stop ${mountUnit}
                trap - EXIT
                ${alertSend} "Offsite backup done" "Safe to unplug the drive" 3 white_check_mark
              '';
            };

            offsite-freshness = {
              description = "Alert when the offsite drive has not been backed up lately";
              unitConfig.OnFailure = "alert-failure@offsite-freshness.service";
              serviceConfig = {
                Type = "oneshot";
                Environment = "ALERT_TOPIC_FILE=${config.blizzard.backup.ntfyTopicFile}";
              };
              script = ''
                last=$(cat ${statusFile} 2>/dev/null || echo 0)
                days=$(( ($(date +%s) - last) / 86400 ))
                if [ "$days" -gt ${toString cfg.maxAgeDays} ]; then
                  ${alertSend} "Offsite backup stale" "Last offsite run $days days ago; plug the drive into ${config.networking.hostName}" 3 warning
                fi
              '';
            };
          };

          timers.offsite-freshness = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "Mon 10:00";
              Persistent = true;
            };
          };
        };
      };
    };
}
