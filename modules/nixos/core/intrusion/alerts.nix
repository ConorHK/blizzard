_: {
  flake.modules.nixos.alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.blizzard.alerts.send = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "alert-send <title> <message> [priority] [comma-tags] — pushes to the ntfy security topic.";
      };

      config = {
        age.secrets.alert-ntfy-topic.rekeyFile = ./secrets/alert-ntfy-topic.age;

        systemd.services."alert-failure@" = {
          description = "Report a failed unit via ntfy";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe config.blizzard.alerts.send} 'Unit failed' '%i failed — check journalctl -u %i' 4 warning";
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
            . ${config.age.secrets.alert-ntfy-topic.path}

            jq -n \
              --arg topic "$NTFY_TOPIC" \
              --arg title "${config.networking.hostName}: $title" \
              --arg message "$message" \
              --argjson priority "$priority" \
              --arg tags "$tags" \
              '{topic: $topic, title: $title, message: $message, priority: $priority, tags: ($tags | split(","))}' \
              | curl -fsS --max-time 20 --retry 3 --retry-delay 5 -o /dev/null \
                  -H "Content-Type: application/json" --data-binary @- https://ntfy.sh
          '';
        };
      };
    };
}
