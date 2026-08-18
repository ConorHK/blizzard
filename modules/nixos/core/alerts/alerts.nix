_: {
  flake.modules.nixos.alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.alerts;

      drain = pkgs.writeShellApplication {
        name = "alert-drain";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          findutils
          util-linux
        ];
        text = ''
          # One sender at a time, or the inline drain and the timer post the same file twice.
          exec 9>"${cfg.spoolDir}/.lock"
          flock -n 9 || exit 0

          # -mmin rather than -mtime, which counts whole days and would keep these two.
          find ${cfg.spoolDir} -name '*.json' -mmin +1440 -print -delete

          for alert in ${cfg.spoolDir}/*.json; do
            [ -e "$alert" ] || break

            code=$(curl -sS -o /dev/null -w '%{http_code}' \
                     --connect-timeout 5 --max-time 20 \
                     -H "Content-Type: application/json" \
                     --data-binary @"$alert" ${cfg.endpoint}) || code=000

            case $code in
              2*)
                rm -f "$alert"
                ;;
              408 | 429)
                echo "ntfy is throttling, alerts stay queued in ${cfg.spoolDir}"
                break
                ;;
              4*)
                echo "ntfy rejected $alert with HTTP $code, dropping it"
                rm -f "$alert"
                ;;
              *)
                echo "ntfy unreachable, alerts stay queued in ${cfg.spoolDir}"
                break
                ;;
            esac
          done
        '';
      };
    in
    {
      options.blizzard.alerts = {
        send = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "alert-send <title> <message> [priority] [comma-tags] — queues an alert for the ntfy security topic and tries to deliver it.";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://ntfy.sh";
          description = "Base URL alerts are POSTed to.";
        };

        topicFile = lib.mkOption {
          type = lib.types.path;
          description = "File sourced for NTFY_TOPIC; override per-call with ALERT_TOPIC_FILE.";
        };

        spoolDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/alert-spool";
          description = "Undelivered alerts wait here. Payloads carry the topic, so this stays root-only, and any sandboxed caller of alert-send needs it in ReadWritePaths.";
        };
      };

      config = {
        systemd.tmpfiles.rules = [ "d ${cfg.spoolDir} 0700 root root -" ];

        systemd = {
          services = {
            "alert-failure@" = {
              description = "Report a failed unit via ntfy";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${lib.getExe cfg.send} 'Unit failed' '%i failed — check journalctl -u %i' 4 warning";
              };
            };

            alert-drain = {
              description = "Deliver queued alerts";
              unitConfig.ConditionPathExistsGlob = "${cfg.spoolDir}/*.json";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = lib.getExe drain;
              };
            };
          };
          timers.alert-drain = {
            description = "Retry alerts that could not be delivered";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1min";
              OnUnitActiveSec = "1min";
            };
          };
        };

        blizzard.alerts.send = pkgs.writeShellApplication {
          name = "alert-send";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.jq
            drain
          ];
          text = ''
            title=$1
            message=$2
            priority=''${3:-4}
            tags=''${4:-warning}

            NTFY_TOPIC=""
            # shellcheck source=/dev/null
            . "''${ALERT_TOPIC_FILE:-${cfg.topicFile}}"

            payload=$(jq -n \
              --arg topic "$NTFY_TOPIC" \
              --arg title "${config.networking.hostName}: $title" \
              --arg message "$message" \
              --argjson priority "$priority" \
              --arg tags "$tags" \
              '{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(","))}')

            # Spooled under a name the drain ignores, then renamed, so an alert
            # outlives an outage or a reboot and is never read half-written.
            pending=$(mktemp ${cfg.spoolDir}/.pending-XXXXXX)
            printf '%s\n' "$payload" > "$pending"
            mv "$pending" "${cfg.spoolDir}/$(date +%s%N)-''${pending##*-}.json"

            alert-drain
          '';
        };
      };
    };
}
