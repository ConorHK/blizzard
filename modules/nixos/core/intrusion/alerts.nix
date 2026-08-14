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
    in
    {
      options.blizzard.alerts = {
        send = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "alert-send <title> <message> [priority] [comma-tags] — pushes to the ntfy security topic.";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://ntfy.sh";
          description = "Base URL alerts are POSTed to.";
        };

        topicFile = lib.mkOption {
          type = lib.types.path;
          description = "File sourced for NTFY_TOPIC.";
        };
      };

      config = {
        systemd.services."alert-failure@" = {
          description = "Report a failed unit via ntfy";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe cfg.send} 'Unit failed' '%i failed — check journalctl -u %i' 4 warning";
          };
        };

        blizzard.alerts.send = pkgs.writeShellApplication {
          name = "alert-send";
          runtimeInputs = with pkgs; [
            curl
            jq
          ];
          text = ''
            title=$1
            message=$2
            priority=''${3:-4}
            tags=''${4:-warning}

            NTFY_TOPIC=""
            # shellcheck source=/dev/null
            . ${cfg.topicFile}

            jq -n \
              --arg topic "$NTFY_TOPIC" \
              --arg title "${config.networking.hostName}: $title" \
              --arg message "$message" \
              --argjson priority "$priority" \
              --arg tags "$tags" \
              '{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(","))}' \
              | curl -fsS --max-time 20 --retry 3 --retry-delay 5 -o /dev/null \
                  -H "Content-Type: application/json" --data-binary @- ${cfg.endpoint}
          '';
        };
      };
    };
}
