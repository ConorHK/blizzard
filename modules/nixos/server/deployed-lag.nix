_: {
  flake.modules.nixos.deployed-lag =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.deployedLag;

      check = pkgs.writeShellApplication {
        name = "deployed-lag-check";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.git
        ];
        text = ''
          remote=$1
          threshold=$2
          state=''${STATE_DIRECTORY:?}
          cache=$state/repo.git
          # "<main sha> <first seen> [alerted]"
          pending=$state/pending
          misses=$state/fetch-failures

          sync() {
            if [ ! -d "$cache" ]; then
              rm -rf "$cache.tmp"
              git clone -q --bare --filter=blob:none "$remote" "$cache.tmp" && mv "$cache.tmp" "$cache"
            fi
            [ -d "$cache" ] && git -C "$cache" fetch -q origin \
              '+refs/heads/main:refs/heads/main' '+refs/heads/deployed:refs/heads/deployed'
          }

          # Rides out short GitHub outages.
          if ! sync; then
            n=$(( $(cat "$misses" 2>/dev/null || echo 0) + 1 ))
            echo "$n" >"$misses"
            echo "fetch failed, $n in a row"
            if (( n == 3 )); then
              alert-send "Deploy check blind" "Cannot fetch the repo for 3 checks." 4 warning
            fi
            exit 0
          fi
          if (( $(cat "$misses" 2>/dev/null || echo 0) >= 3 )); then
            alert-send "Deploy check back" "The repo fetches again." 3 "+1"
          fi
          rm -f "$misses"

          contains() {
            git -C "$cache" merge-base --is-ancestor "$1" "$2"
          }

          now=$(date +%s)
          main=$(git -C "$cache" rev-parse main)
          if [ -e "$pending" ]; then
            read -r sha since alerted <"$pending" || true
            alerted=''${alerted:-}
            # A rewritten main drops the old sha.
            if ! contains "$sha" main; then
              sha=$main
            fi
            if contains "$sha" deployed; then
              rm "$pending"
              if [ -n "$alerted" ]; then
                alert-send "Deploys resumed" "CI promoted main to deployed again." 3 "+1"
              fi
            else
              if (( now - since > threshold * 3600 )) && [ -z "$alerted" ]; then
                alert-send "Deploys stalled" \
                  "CI has not promoted ''${sha:0:8} for $(( (now - since) / 3600 ))h." 4 warning
                alerted=alerted
              fi
              echo "$sha $since $alerted" >"$pending"
            fi
          fi

          if [ ! -e "$pending" ] && ! contains "$main" deployed; then
            echo "$main $now" >"$pending"
          fi
        '';
      };
    in
    {
      options.blizzard.deployedLag = {
        remote = lib.mkOption {
          type = lib.types.str;
          description = "Repository whose deployed branch must follow main.";
        };

        thresholdHours = lib.mkOption {
          type = lib.types.ints.positive;
          default = 12;
          description = "Hours a main commit may wait for promotion.";
        };
      };

      config = {
        environment.systemPackages = [ check ];

        systemd.services.deployed-lag = {
          description = "Alert when deployed stops following main";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          # The watchdog must not fail silently.
          unitConfig.OnFailure = "alert-failure@deployed-lag.service";
          environment.HOME = "/var/lib/deployed-lag";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.escapeShellArgs [
              (lib.getExe check)
              cfg.remote
              (toString cfg.thresholdHours)
            ];
            StateDirectory = "deployed-lag";
            ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            ProtectSystem = "strict";
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };

        systemd.timers.deployed-lag = {
          description = "Check deployed against main hourly";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "15min";
            OnUnitActiveSec = "1h";
          };
        };
      };
    };
}
