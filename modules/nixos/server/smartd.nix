_: {
  flake.modules.nixos.smartd =
    {
      config,
      pkgs,
      ...
    }:
    let
      # smartd has no native ntfy channel, only mail/wall/x11. Its `-M exec` hook
      # runs an arbitrary script on a detected problem, with SMARTD_* in the env.
      # Reuses the root-owned restic ntfy topic (this host already alerts there).
      notify = pkgs.writeShellScript "smartd-ntfy" ''
        set -euo pipefail
        . ${config.age.secrets.restic-ntfy-topic.path}
        ${pkgs.curl}/bin/curl -fsS https://ntfy.sh \
          -H "Content-Type: application/json" \
          -d "$(${pkgs.jq}/bin/jq -n \
            --arg topic "$NTFY_TOPIC" \
            --arg msg "$SMARTD_MESSAGE" \
            --arg dev "''${SMARTD_DEVICESTRING:-unknown}" \
            '{topic: $topic, title: "SMART warning on ${config.networking.hostName} (\($dev))", message: $msg, priority: 5, tags: ["rotating_light"]}')"
      '';
    in
    {
      services.smartd = {
        enable = true;
        autodetect = true;
        # Disable the built-in channels: `wall` (the default) is useless on a
        # headless box and would inject a second, duplicate `-M exec` handler
        # alongside ours below.
        notifications = {
          wall.enable = false;
          mail.enable = false;
          x11.enable = false;
        };
        # -a: monitor everything. -o on: SMART Automatic Offline Testing.
        # -s: short self-test daily @02, long self-test Sundays @03 (background,
        # low-impact, ahead of the 03:00 backup).
        # -M exec: fire the ntfy hook instead of mail on any detected problem.
        defaults.monitored = "-a -o on -s (S/../.././02|L/../../7/03) -m <nomailer> -M exec ${notify}";
      };
    };
}
