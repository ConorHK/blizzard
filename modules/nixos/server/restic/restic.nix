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

      allPaths = lib.unique (cfg.paths ++ cfg.dumpPaths);

      useZfs = cfg.zfsDatasets != { };
      snapRoot = "/run/restic-zfs";
      zfs = lib.getExe' config.boot.zfs.package "zfs";
      # Containers run under the backup user's manager.
      userCtl =
        action:
        lib.concatMapStringsSep "\n" (
          c: "${pkgs.systemd}/bin/systemctl --user -M containers@ ${action} ${c}.service"
        ) pauseContainers;
      eachDataset = f: lib.concatStringsSep "\n" (lib.mapAttrsToList f cfg.zfsDatasets);

      repoEnv = [
        "RESTIC_REPOSITORY=${cfg.repository}"
        "RESTIC_PASSWORD_FILE=${cfg.passwordFile}"
        "ALERT_TOPIC_FILE=${cfg.ntfyTopicFile}"
      ];
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

        dumpPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Dump directories to back up; every file must stay under 26h old.";
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
              requires = lib.optional useZfs "restic-zfs-snapshot.service";
              after = lib.optional useZfs "restic-zfs-snapshot.service";
              serviceConfig = {
                # Yield CPU during the run; ZFS ignores ionice, so no I/O class here
                Nice = 19;
                # Read owner-only service data, no writes.
                AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
                # Restic reads the snapshot at live paths.
                BindReadOnlyPaths = lib.mapAttrsToList (_: mp: "${snapRoot}${mp}:${mp}") cfg.zfsDatasets;
              };
            };

            restic-zfs-snapshot = lib.mkIf useZfs {
              description = "Snapshot ZFS datasets for restic";
              unitConfig.OnFailure = "alert-failure@restic-zfs-snapshot.service";
              path = [ pkgs.util-linux ];
              serviceConfig.Type = "oneshot";
              script = ''
                set -euo pipefail
                ${eachDataset (
                  ds: mp: ''
                    if mountpoint -q ${snapRoot}${mp}; then umount ${snapRoot}${mp}; fi
                    if ${zfs} list -H -t snapshot ${ds}@restic >/dev/null 2>&1; then
                      ${zfs} destroy ${ds}@restic
                    fi
                  ''
                )}
                ${userCtl "stop"}
                trap '${userCtl "start"}' EXIT
                # One command: all datasets, one instant.
                ${zfs} snapshot ${lib.concatMapStringsSep " " (ds: "${ds}@restic") (lib.attrNames cfg.zfsDatasets)}
                ${userCtl "start"}
                trap - EXIT
                # Explicit mounts; .zfs automounts expire mid-backup.
                ${eachDataset (
                  ds: mp: ''
                    mkdir -p ${snapRoot}${mp}
                    ${config.boot.zfs.package}/bin/mount.zfs ${ds}@restic ${snapRoot}${mp}
                  ''
                )}
              '';
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
                Environment = repoEnv ++ [ "RESTIC_CACHE_DIR=%C/restic-freshness" ];
              };
              script = ''
                set -uo pipefail
                alert() {
                  ${lib.getExe config.blizzard.alerts.send} "Backup stale" "$1" 4 warning
                }
                # A dead dump job leaves old dumps restic keeps saving.
                for dir in ${lib.escapeShellArgs cfg.dumpPaths}; do
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

            # Weekly proof the real repo restores.
            restic-restore-drill = {
              description = "Restore sample files and compare to disk";
              unitConfig.OnFailure = "alert-failure@restic-restore-drill.service";
              path = [
                pkgs.restic
                pkgs.jq
                pkgs.coreutils
                pkgs.diffutils
                pkgs.gawk
                pkgs.gzip
                pkgs.sqlite
              ];
              serviceConfig = {
                Type = "oneshot";
                Nice = 19;
                PrivateTmp = true;
                EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
                CacheDirectory = "restic-restore-drill";
                CacheDirectoryMode = "0700";
                Environment = repoEnv ++ [ "RESTIC_CACHE_DIR=%C/restic-restore-drill" ];
              };
              script = ''
                set -uo pipefail
                alert() {
                  ${lib.getExe config.blizzard.alerts.send} "Restore drill failed" "$1" 4 warning
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
                      # pg_dump writes this footer last.
                      if restic dump "$id" "$f" | gzip -dc | tail -n 5 | grep -q 'dump complete'; then
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

          timers.restic-restore-drill = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "Sun 12:00";
              Persistent = true;
            };
          };
        };

        services.restic.backups.service-data = {
          user = "containers";
          paths = allPaths;
          inherit (cfg)
            repository
            exclude
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
          # `|| true`: no repo yet before `initialize`.
          backupPrepareCommand = ''
            ${pkgs.restic}/bin/restic unlock || true
            ${lib.optionalString (!useZfs && pauseContainers != [ ]) (mkContainerScript "stop")}
          '';
          backupCleanupCommand = lib.optionalString (
            !useZfs && pauseContainers != [ ]
          ) "${mkContainerScript "start"}";
        };
      };
    };
}
