_: {
  flake.modules.nixos.login-alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # SD_MESSAGE_SESSION_START. logind rewords the human-readable text between
      # releases; the message id and its SESSION_ID/USER_ID fields are stable.
      sessionStart = "8d45620c1a4348dbb17410da57c60c66";

      watcher = pkgs.writeShellApplication {
        name = "login-alerts";
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

          notify() {
            if throttled; then
              echo "rate limit reached, suppressed: $2"
              return
            fi
            alert-send "$1" "$2" 4 key || echo "alert-send failed for: $2"
          }

          # A session that has already ended reports nothing, so every caller
          # has to cope with these being empty.
          session_props() {
            Class=""
            Service=""
            RemoteHost=""
            while IFS='=' read -r key value; do
              case $key in
                Class) Class=$value ;;
                Service) Service=$value ;;
                RemoteHost) RemoteHost=$value ;;
                *) ;;
              esac
            done < <(
              loginctl show-session "$1" \
                --property=Class --property=Service --property=RemoteHost \
                < /dev/null 2>/dev/null || true
            )
          }

          # logind opens a session for every login path that goes through PAM,
          # so sshd, console and greetd all arrive here as one kind of event.
          journalctl --follow --lines=0 --output=json \
            --cursor-file=/var/lib/login-alerts/cursor \
            MESSAGE_ID=${sessionStart} \
            | jq --unbuffered -r '[.USER_ID, .SESSION_ID] | @tsv' \
            | while IFS=$'\t' read -r user session; do
                session_props "$session"

                # The per-user systemd manager opens a session of its own, as do
                # greeters; only a real login has class "user". An ended session
                # reports no class at all, and was far likelier to be a login.
                if [ -n "$Class" ] && [ "$Class" != user ]; then
                  continue
                fi

                message="$user logged in"
                if [ -n "$Service" ]; then message="$message via $Service"; fi
                if [ -n "$RemoteHost" ]; then message="$message from $RemoteHost"; fi

                notify "Login" "$message"
              done
        '';
      };
    in
    {
      systemd.services.login-alerts = {
        description = "Alert on logins";
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
          OnFailure = "alert-failure@login-alerts.service";
        };

        serviceConfig = {
          ExecStart = lib.getExe watcher;
          Restart = "always";
          RestartSec = 10;
          StateDirectory = "login-alerts";
          ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict";
        };
      };
    };
}
