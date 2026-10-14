_: {
  flake.modules.nixos.gatus-watch =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.gatusWatch;

      probe = pkgs.writeShellApplication {
        name = "gatus-watch";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.curl
        ];
        text = ''
          url=$1
          limit=$2
          state=''${STATE_DIRECTORY:?}/failures
          failures=$(cat "$state" 2>/dev/null || echo 0)

          if curl -fsS --max-time 10 -o /dev/null "$url"; then
            if (( failures >= limit )); then
              alert-send "Monitor back" "gatus answers again." 3 "+1"
            fi
            rm -f "$state"
            exit 0
          fi

          failures=$(( failures + 1 ))
          echo "$failures" >"$state"
          # Page once per outage.
          if (( failures == limit )); then
            alert-send "Monitor down" "No answer from $url for $limit checks." 4 warning
          fi
        '';
      };
    in
    {
      options.blizzard.gatusWatch = {
        url = lib.mkOption {
          type = lib.types.str;
          description = "gatus health endpoint to probe.";
        };

        failures = lib.mkOption {
          type = lib.types.ints.positive;
          default = 3;
          description = "Consecutive failed probes before paging; rides out reboots.";
        };
      };

      config = {
        environment.systemPackages = [ probe ];

        systemd.services.gatus-watch = {
          description = "Probe the gatus monitor from outside";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          unitConfig.OnFailure = "alert-failure@gatus-watch.service";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe probe)
              cfg.url
              (toString cfg.failures)
            ];
            StateDirectory = "gatus-watch";
            ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };

        systemd.timers.gatus-watch = {
          description = "Probe the gatus monitor every 5 minutes";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
          };
        };
      };
    };
}
