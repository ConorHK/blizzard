_: {
  flake.modules.nixos.auth-alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      watcher = pkgs.writeShellApplication {
        name = "auth-alerts";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
          config.blizzard.alerts.send
        ];
        text = ''
          window=0
          count=0

          # Cap alerts at 10 per 10 minutes so a flood can't spam the topic.
          throttled() {
            local now
            now=$(date +%s)
            if [ $(( now - window )) -gt 600 ]; then
              window=$now
              count=0
            fi
            count=$(( count + 1 ))
            [ "$count" -gt 10 ]
          }

          journalctl --follow --lines=0 --output=json \
            --cursor-file=/var/lib/auth-alerts/cursor \
            _SYSTEMD_UNIT=sshd.service \
            + SYSLOG_IDENTIFIER=sshd \
            + SYSLOG_IDENTIFIER=sshd-session \
            + SYSLOG_IDENTIFIER=sudo \
            + SYSLOG_IDENTIFIER=su \
            + SYSLOG_IDENTIFIER=tailscaled \
            | jq --unbuffered -r '
                select(.MESSAGE | type == "string")
                | if .SYSLOG_IDENTIFIER == "tailscaled" then "tailscale: " + .MESSAGE
                  else .MESSAGE end
              ' \
            | while IFS= read -r msg; do
                case $msg in
                  # Prefixed sources are matched first so their chatter, which
                  # echoes whole commands, can't hit the substring patterns below.
                  "tailscale: "*"access granted to"*)
                    title="Tailscale SSH login"
                    priority=4
                    tags=key
                    ;;
                  "tailscale: "*"access denied"*)
                    title="Tailscale SSH denied"
                    priority=4
                    tags=warning
                    ;;
                  "tailscale: "*)
                    continue
                    ;;
                  "Accepted "*)
                    title="SSH login"
                    priority=4
                    tags=key
                    ;;
                  *"Failed password"*| *"Invalid user"*| *"Failed publickey"*| *"maximum authentication attempts"*)
                    title="SSH auth failure"
                    priority=3
                    tags=warning
                    ;;
                  *"authentication failure"*| *"NOT in sudoers"*| *"incorrect password attempt"*| *"FAILED su"*)
                    title="Privilege escalation failure"
                    priority=4
                    tags=warning
                    ;;
                  *)
                    continue
                    ;;
                esac

                if throttled; then
                  echo "rate limit reached, suppressed: $msg"
                  continue
                fi

                alert-send "$title" "$msg" "$priority" "$tags" || echo "alert-send failed for: $msg"
              done
        '';
      };
    in
    {
      systemd.services.auth-alerts = {
        description = "Alert on authentication events";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "agenix-install-secrets.service"
        ];
        wants = [ "network-online.target" ];

        unitConfig = {
          # A stale journal cursor replays on restart, so cap a crash loop
          # rather than let it re-alert every 10 seconds forever.
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
          OnFailure = "alert-failure@auth-alerts.service";
        };

        serviceConfig = {
          ExecStart = lib.getExe watcher;
          Restart = "always";
          RestartSec = 10;
          StateDirectory = "auth-alerts";
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };
    };
}
