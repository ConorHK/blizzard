_: {
  flake.modules.nixos.disk-alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.diskAlerts;
      podman = config.virtualisation.podman;

      cleanup = pkgs.writeShellApplication {
        name = "disk-cleanup";
        runtimeInputs = [ config.nix.package ] ++ lib.optional podman.enable podman.package;
        text = ''
          nix-collect-garbage ${cfg.gcOptions}
          ${lib.optionalString podman.enable "podman image prune --all --force"}
        '';
      };

      check = pkgs.writeShellApplication {
        name = "disk-check";
        runtimeInputs = [
          config.blizzard.alerts.send
          cleanup
          pkgs.coreutils
          pkgs.findutils
          pkgs.systemd
        ];
        text = ''
          state=/var/lib/disk-alerts

          usage() {
            df --output=pcent "$1" | tail -n1 | tr -dc '0-9'
          }

          mounts=(${lib.escapeShellArgs cfg.mounts})
          full=()
          for mount in "''${mounts[@]}"; do
            if [ "$(usage "$mount")" -ge ${toString cfg.threshold} ]; then
              full+=("$mount")
            fi
          done
          if [ ''${#full[@]} -gt 0 ]; then
            disk-cleanup
          fi

          for mount in "''${mounts[@]}"; do
            pct=$(usage "$mount")
            stamp="$state/$(systemd-escape --path "$mount")"
            if [ "$pct" -lt ${toString cfg.threshold} ] || ! ${lib.boolToString cfg.page}; then
              rm -f "$stamp"
              continue
            fi
            # Once a day while it stays full.
            if [ -z "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
              alert-send "Disk full" "$mount at $pct% after cleanup" 4 floppy_disk
              touch "$stamp"
            fi
          done
        '';
      };
    in
    {
      options.blizzard.diskAlerts = {
        mounts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = lib.filter (m: config.fileSystems ? ${m}) [
            "/"
            "/nix"
            "/boot"
          ];
          description = "Mount points to watch.";
        };

        threshold = lib.mkOption {
          type = lib.types.ints.between 1 100;
          default = 90;
          description = "Percent used that triggers cleanup, then an alert.";
        };

        page = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Alert when cleanup leaves a disk full.";
        };

        gcOptions = lib.mkOption {
          type = lib.types.str;
          default = config.nix.gc.options;
          description = "Arguments to nix-collect-garbage during cleanup.";
        };
      };

      config.systemd = {
        services.disk-alerts = {
          description = "Clean up and alert on full disks";
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "disk-alerts";
            ExecStart = lib.getExe check;
          };
        };
        timers.disk-alerts = {
          description = "Hourly disk usage check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "10min";
            OnUnitActiveSec = "1h";
          };
        };
      };
    };
}
