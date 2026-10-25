_: {
  flake.modules.nixos.backup =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.blizzard.backup;
      host = config.networking.hostName;
      jobs = lib.filterAttrs (_: job: job.paths != [ ] || job.dumpPaths != [ ]) cfg.jobs;

      zfs = lib.getExe' config.boot.zfs.package "zfs";
      alertSend = lib.getExe config.blizzard.alerts.send;

      jobOptions =
        { name, ... }:
        {
          options = {
            # Backend modules turn this into repository.
            bucket = lib.mkOption {
              type = lib.types.str;
              default = "restic-backup-${name}";
              description = "Bucket the backend stores this job's repository in.";
            };

            repository = lib.mkOption {
              type = lib.types.str;
              description = "Restic repository URL, set by a backend module.";
            };

            user = lib.mkOption {
              type = lib.types.str;
              default = "containers";
              description = "User the backup runs as.";
            };

            schedule = lib.mkOption {
              type = lib.types.str;
              default = "03:00";
              description = "OnCalendar time of the daily backup.";
            };

            paths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Paths to include in the backup.";
            };

            dumpPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Dump directories to back up; every file must stay under 26h old.";
            };

            freshPaths = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Directories whose newest file must stay under freshMaxAge.";
            };

            freshMaxAge = lib.mkOption {
              type = lib.types.ints.positive;
              default = 48;
              description = "Hours a freshPaths directory may go without a new file.";
            };

            freshness = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Alert daily when this job goes stale.";
            };

            zfsDatasets = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                "storage/data" = "/storage/data";
              };
              description = ''
                ZFS datasets, mapped to mountpoints, to back up from a snapshot.
                Paused containers then stop only while the snapshot is taken.
              '';
            };

            exclude = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Patterns to leave out of the backup.";
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
          };
        };

      mkJob =
        name: job:
        let
          unit = "restic-backups-${name}";
          allPaths = lib.unique (job.paths ++ job.dumpPaths);
          useZfs = job.zfsDatasets != { };
          snapName = "restic-${name}";
          snapRoot = "/run/restic-zfs/${name}";
          eachDataset = f: lib.concatStringsSep "\n" (lib.mapAttrsToList f job.zfsDatasets);

          containerScript =
            action:
            pkgs.writeShellScript "restic-${action}-containers" ''
              ${lib.concatMapStringsSep "\n" (
                c: "XDG_RUNTIME_DIR=/run/user/$(id -u) ${pkgs.systemd}/bin/systemctl --user ${action} ${c}.service"
              ) job.pauseContainers}
            '';
          # Containers run under the backup user's manager.
          userCtl =
            action:
            lib.concatMapStringsSep "\n" (
              c: "${pkgs.systemd}/bin/systemctl --user -M containers@ ${action} ${c}.service"
            ) job.pauseContainers;

          repoService = cache: {
            Type = "oneshot";
            EnvironmentFile = lib.optional (job.environmentFile != null) job.environmentFile;
            # Units get no $HOME, and restic refuses to run without a cache.
            CacheDirectory = cache;
            CacheDirectoryMode = "0700";
            Environment = [
              "RESTIC_REPOSITORY=${job.repository}"
              "RESTIC_PASSWORD_FILE=${job.passwordFile}"
              "RESTIC_CACHE_DIR=%C/${cache}"
              "ALERT_TOPIC_FILE=${cfg.ntfyTopicFile}"
            ];
          };
        in
        {
          services.restic.backups.${name} = {
            inherit (job) user;
            paths = allPaths;
            inherit (job)
              repository
              exclude
              passwordFile
              environmentFile
              ;
            # Create the repo on first run instead of failing. Idempotent, and the
            # difference between a working DR restore and a silent failure at the
            # worst possible time if the bucket ever has to be recreated.
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
              OnCalendar = job.schedule;
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
            # `|| true`: no repo yet before `initialize`.
            backupPrepareCommand = ''
              ${pkgs.restic}/bin/restic unlock || true
              ${lib.optionalString (!useZfs && job.pauseContainers != [ ]) (containerScript "stop")}
            '';
            backupCleanupCommand = lib.optionalString (
              !useZfs && job.pauseContainers != [ ]
            ) "${containerScript "start"}";
          };

          systemd.services = {
            ${unit} = {
              unitConfig.OnFailure = "restic-backups-notify-failure@${name}.service";
              requires = lib.optional useZfs "restic-zfs-snapshot-${name}.service";
              after = lib.optional useZfs "restic-zfs-snapshot-${name}.service";
              serviceConfig = {
                # Yield CPU during the run; ZFS ignores ionice, so no I/O class here
                Nice = 19;
                # Read owner-only service data, no writes.
                AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
                # Restic reads the snapshot at live paths.
                BindReadOnlyPaths = lib.mapAttrsToList (_: mp: "${snapRoot}${mp}:${mp}") job.zfsDatasets;
              };
            };

            "restic-zfs-snapshot-${name}" = lib.mkIf useZfs {
              description = "Snapshot ZFS datasets for restic job ${name}";
              unitConfig.OnFailure = "alert-failure@restic-zfs-snapshot-${name}.service";
              path = [ pkgs.util-linux ];
              serviceConfig.Type = "oneshot";
              script = ''
                set -euo pipefail
                ${eachDataset (
                  ds: mp: ''
                    if mountpoint -q ${snapRoot}${mp}; then umount ${snapRoot}${mp}; fi
                    if ${zfs} list -H -t snapshot ${ds}@${snapName} >/dev/null 2>&1; then
                      ${zfs} destroy ${ds}@${snapName}
                    fi
                  ''
                )}
                ${userCtl "stop"}
                trap '${userCtl "start"}' EXIT
                # One command: all datasets, one instant.
                ${zfs} snapshot ${
                  lib.concatMapStringsSep " " (ds: "${ds}@${snapName}") (lib.attrNames job.zfsDatasets)
                }
                ${userCtl "start"}
                trap - EXIT
                # Explicit mounts; .zfs automounts expire mid-backup.
                ${eachDataset (
                  ds: mp: ''
                    mkdir -p ${snapRoot}${mp}
                    ${config.boot.zfs.package}/bin/mount.zfs ${ds}@${snapName} ${snapRoot}${mp}
                  ''
                )}
              '';
            };

            "restic-freshness-${name}" = lib.mkIf job.freshness {
              description = "Alert if restic job ${name} goes stale";
              # The watchdog itself must not fail silently.
              unitConfig.OnFailure = "alert-failure@restic-freshness-${name}.service";
              path = [
                pkgs.restic
                pkgs.jq
                pkgs.coreutils
                pkgs.findutils
              ];
              # Root, not the backup user: the ntfy topic is root-owned.
              serviceConfig = repoService "restic-freshness-${name}";
              script = ''
                set -uo pipefail
                alert() {
                  ${alertSend} "Backup stale" "$1" 4 warning
                }
                now=$(date +%s)
                # A dead dump job leaves old dumps restic keeps saving.
                for dir in ${lib.escapeShellArgs job.dumpPaths}; do
                  if [ -z "$(find "$dir" -type f -print -quit 2>/dev/null)" ]; then
                    alert "No dumps in $dir"
                    continue
                  fi
                  stale=$(find "$dir" -type f -mmin +1560)
                  if [ -n "$stale" ]; then
                    echo "$stale"
                    alert "$(wc -l <<<"$stale") dumps over 26h old in $dir"
                  fi
                done
                # A source that stops writing leaves old files restic keeps saving.
                # Skips syncthing markers, which never change.
                for dir in ${lib.escapeShellArgs job.freshPaths}; do
                  newest=$(find "$dir" -name '.st*' -prune -o -type f -printf '%T@\n' 2>/dev/null \
                    | sort -n | tail -n 1)
                  if [ -z "$newest" ]; then
                    alert "No files in $dir"
                  elif [ $(( now - ''${newest%.*} )) -gt ${toString (job.freshMaxAge * 3600)} ]; then
                    alert "No new files in $dir for $(( (now - ''${newest%.*}) / 3600 ))h"
                  fi
                done
                # `|| true`: the generated job script runs with -e, so an
                # unreachable or uninitialized repo would abort before alerting.
                # restic's stderr goes to the journal, not /dev/null, so the
                # reason an alert fired is recoverable afterwards.
                newest=$(restic snapshots --json --latest 1 \
                  | jq -r 'max_by(.time).time // empty' || true)
                if [ -z "$newest" ]; then
                  alert "${name}: no snapshots, check journalctl -u ${unit}"
                  exit 0
                fi
                age=$(( now - $(date -d "$newest" +%s) ))
                # 26h: one daily backup plus margin for a slow run.
                if [ "$age" -gt 93600 ]; then
                  alert "${name}: newest snapshot is $((age / 3600))h old"
                fi
              '';
            };

            # Weekly proof the real repo restores.
            "restic-restore-drill-${name}" = {
              description = "Restore samples of restic job ${name} and compare";
              unitConfig.OnFailure = "alert-failure@restic-restore-drill-${name}.service";
              path = [
                pkgs.restic
                pkgs.jq
                pkgs.coreutils
                pkgs.diffutils
                pkgs.gawk
                pkgs.gzip
                pkgs.sqlite
              ];
              serviceConfig = repoService "restic-restore-drill-${name}" // {
                Nice = 19;
                PrivateTmp = true;
              };
              script = ''
                set -uo pipefail
                alert() {
                  ${alertSend} "Restore drill failed" "${name}: $1" 4 warning
                }
                snap=$(restic snapshots --json --latest 1 | jq -c 'max_by(.time) // empty' || true)
                if [ -z "$snap" ]; then
                  alert "No snapshot to restore from"
                  exit 0
                fi
                id=$(jq -r .id <<<"$snap")
                taken=$(date -d "$(jq -r .time <<<"$snap")" +%s)

                listing=$(mktemp)
                if ! restic ls --json "$id" | jq -r 'select(.type == "file") | .path' >"$listing"; then
                  alert "Could not list latest snapshot"
                  exit 0
                fi

                checked=0
                missing=()
                bad=()
                for root in ${lib.escapeShellArgs allPaths}; do
                  if ! jq -e --arg p "$root" 'any(.paths[]; . == $p)' <<<"$snap" >/dev/null; then
                    missing+=("$root")
                    continue
                  fi
                  while IFS= read -r f; do
                    # Skip files changed or gone since. The hour
                    # covers writes between ZFS snapshot and restic.
                    mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
                    [ "$mtime" -lt $((taken - 3600)) ] || continue
                    if restic dump "$id" "$f" | cmp -s - "$f"; then
                      checked=$((checked + 1))
                    else
                      bad+=("$f")
                    fi
                  done < <(awk -v p="$root/" 'index($0, p) == 1' "$listing" | shuf -n 3)
                done

                # Matching bytes can still be a torn database.
                work=$(mktemp -d -p /var/tmp)
                dbs=0
                corrupt=()
                while IFS= read -r f; do
                  case "$f" in
                    *.sql.gz)
                      # pg_dump and mariadb-dump write this footer last.
                      if restic dump "$id" "$f" | gzip -dc | tail -n 5 | grep -qi 'dump complete'; then
                        dbs=$((dbs + 1))
                      else
                        corrupt+=("$f")
                      fi
                      ;;
                    *)
                      rm -f "$work"/check.db*
                      if ! restic dump "$id" "$f" >"$work/check.db"; then
                        corrupt+=("$f")
                        continue
                      fi
                      # Some apps use .db for other formats.
                      printf 'SQLite format 3\0' | cmp -s -n 16 - "$work/check.db" || continue
                      if [ "$(sqlite3 "$work/check.db" 'PRAGMA integrity_check' 2>&1)" = ok ]; then
                        dbs=$((dbs + 1))
                      else
                        corrupt+=("$f")
                      fi
                      ;;
                  esac
                done < <(grep -E '\.(db|sqlite3?|sql\.gz)$' "$listing")
                rm -rf "$work"

                if [ "''${#missing[@]}" -gt 0 ]; then
                  printf 'missing from snapshot: %s\n' "''${missing[@]}"
                  alert "''${#missing[@]} backup paths missing from snapshot"
                fi
                if [ "''${#bad[@]}" -gt 0 ]; then
                  printf 'differs from disk: %s\n' "''${bad[@]}"
                  alert "''${#bad[@]} restored files differ from disk"
                fi
                if [ "''${#corrupt[@]}" -gt 0 ]; then
                  printf 'corrupt database: %s\n' "''${corrupt[@]}"
                  alert "''${#corrupt[@]} restored databases are corrupt"
                fi
                if [ "$checked" -eq 0 ] && [ "''${#bad[@]}" -eq 0 ] && [ "''${#missing[@]}" -eq 0 ]; then
                  alert "Restore drill compared no files"
                fi
                echo "restore drill: $checked files match, $dbs databases intact"
              '';
            };
          };

          systemd.timers = {
            # Dead-man's switch: OnFailure only fires when a run *fails*. A timer
            # that never triggers (host off at backup time, systemd wedged) produces
            # no backup and no alert. This reads the real repo daily, so it catches
            # silent non-runs and empty backups alike.
            "restic-freshness-${name}" = lib.mkIf job.freshness {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "10:00";
                Persistent = true;
              };
            };

            "restic-restore-drill-${name}" = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "Sun 12:00";
                Persistent = true;
              };
            };
          };
        };

      built = lib.mapAttrsToList mkJob jobs;
    in
    {
      options.blizzard.backup = {
        jobs = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule jobOptions);
          default = { };
          description = "Restic jobs, each with its own repository. Jobs with no paths are skipped.";
        };

        ntfyTopicFile = lib.mkOption {
          type = lib.types.path;
          description = "File sourced for the NTFY_TOPIC backup alerts go to.";
        };
      };

      config = {
        # The host job predates jobs; its bucket keeps the host name.
        blizzard.backup.jobs.service-data.bucket = lib.mkDefault "restic-backup-${host}";

        services.restic.backups = lib.mkMerge (map (job: job.services.restic.backups) built);

        systemd.services = lib.mkMerge (
          [
            {
              "restic-backups-notify-failure@" = {
                description = "Notify restic backup failure via ntfy";
                serviceConfig = {
                  Type = "oneshot";
                  Environment = "ALERT_TOPIC_FILE=${cfg.ntfyTopicFile}";
                  ExecStart = "${alertSend} 'Backup failed' 'restic backup %i failed, check journalctl -u restic-backups-%i' 4 warning";
                };
              };
            }
          ]
          ++ map (job: job.systemd.services) built
        );

        systemd.timers = lib.mkMerge (map (job: job.systemd.timers) built);
      };
    };
}
