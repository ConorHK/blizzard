_: {
  flake.modules.nixos.aqua-booking =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.aqua-booking;

      app = pkgs.python3.pkgs.buildPythonApplication {
        pname = "aqua-booking";
        version = "0.1.0";
        pyproject = true;
        src = ./src;
        build-system = [ pkgs.python3.pkgs.setuptools ];
        dependencies = [ pkgs.python3.pkgs.tzdata ];
        doCheck = false;
        # Importing every submodule turns the build into a cheap syntax/import gate.
        pythonImportsCheck = [
          "aqua_booking"
          "aqua_booking.api"
          "aqua_booking.auth"
          "aqua_booking.config"
          "aqua_booking.log"
          "aqua_booking.notify"
          "aqua_booking.retry"
          "aqua_booking.run"
          "aqua_booking.store"
        ];
        meta.mainProgram = "aqua-booking";
      };

      # Public half only: the gym, the times and the login live in the secret.
      configJson = (pkgs.formats.json { }).generate "aqua-booking.json" {
        inherit (cfg)
          className
          timezone
          releaseHorizonDays
          ;
        api = {
          inherit (cfg) subscriptionKey userAgent;
          base = cfg.apiBase;
          origin = "https://nh-booking-microsite.nuffieldhealth.com";
        };
        auth = {
          instance = cfg.authInstance;
          tenant = "mynuffield.onmicrosoft.com";
          policy = "B2C_1A_NUFFV2_SignInOrSignUpLoA1";
          clientId = "d88bdc88-b6a5-48a3-9619-7311cd904761";
          scope = "openid https://mynuffield.onmicrosoft.com/BookingAPIM/booking_api_access";
          redirectUri = "https://nh-booking-microsite.nuffieldhealth.com/auth/callback/";
        };
        retry = {
          inherit (cfg.retry)
            budgetSeconds
            baseSeconds
            maxBackoffSeconds
            maxRetryAfterSeconds
            ;
        };
        stateDir = "/var/lib/aqua-booking";
      };

      start = pkgs.writeShellScript "aqua-booking-start" ''
        exec ${lib.getExe app} \
          --config ${configJson} \
          --secrets "$CREDENTIALS_DIRECTORY/secrets" "$@"
      '';

      runEnvironment = {
        ALERT_SEND = lib.getExe config.blizzard.alerts.send;
        AQUA_SUCCESS_TOPIC_FILE = "${cfg.successTopicFile}";
        TZDIR = "${pkgs.tzdata}/share/zoneinfo";
        # Without this the journal gets every line at exit, losing the timeline.
        PYTHONUNBUFFERED = "1";
      };

      # Shared so the dry-run entrypoint cannot drift from the unit it stands in for.
      runServiceConfig = {
        Type = "oneshot";
        LoadCredential = "secrets:${cfg.secretsFile}";
        StateDirectory = "aqua-booking";
        # 0700: the state dir holds the booking ledger.
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/aqua-booking";
        NoNewPrivileges = true;
        ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };

      # Credentials only exist inside the unit, so drive the unit and replay the
      # journal for exactly that invocation rather than running the app directly.
      dryRun = pkgs.writeShellScriptBin "aqua-booking-dry-run" ''
        set -uo pipefail
        # Anchor on a cursor taken before the run: a finished oneshot reports an
        # empty InvocationID, and keying off that replayed every earlier run.
        cursor=$(${pkgs.systemd}/bin/journalctl -n 1 --show-cursor 2>/dev/null \
          | ${pkgs.gnused}/bin/sed -n 's/^-- cursor: //p')
        rc=0
        ${pkgs.systemd}/bin/systemctl start aqua-booking-dry-run.service || rc=$?
        ${pkgs.systemd}/bin/journalctl --sync
        if [ -n "$cursor" ]; then
          ${pkgs.systemd}/bin/journalctl --after-cursor "$cursor" \
            -u aqua-booking-dry-run.service -o cat --no-pager
        else
          ${pkgs.systemd}/bin/journalctl -u aqua-booking-dry-run.service \
            -o cat --no-pager --since "-1min"
        fi
        exit "$rc"
      '';
    in
    {
      options.blizzard.aqua-booking = {
        className = lib.mkOption {
          type = lib.types.str;
          default = "Aqua Aerobics";
        };
        timezone = lib.mkOption {
          type = lib.types.str;
          default = "Europe/London";
        };
        releaseHorizonDays = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = "Days ahead a class opens at 07:00.";
        };
        successTopicFile = lib.mkOption {
          type = lib.types.path;
          default = config.blizzard.alerts.topicFile;
          defaultText = lib.literalExpression "config.blizzard.alerts.topicFile";
          description = "File sourced for NTFY_TOPIC on booking confirmations. Defaults to the alert topic; point it at a dedicated agenix secret to split the two.";
        };
        subscriptionKey = lib.mkOption {
          type = lib.types.str;
          default = "882ee8ab406042dd9da8045dc58874a3";
          description = "Public APIM key from the booking site bundle; re-extract if calls start 401ing on the key.";
        };
        apiBase = lib.mkOption {
          type = lib.types.str;
          default = "https://api.nuffieldhealth.com/booking/";
          description = "APIM gateway base URL; overridden by the VM test to point at a local stub.";
        };
        authInstance = lib.mkOption {
          type = lib.types.str;
          default = "https://account.nuffieldhealth.com/";
          description = "Azure AD B2C instance base URL; overridden by the VM test to point at a local stub.";
        };
        userAgent = lib.mkOption {
          type = lib.types.str;
          default = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
        };
        retry = {
          budgetSeconds = lib.mkOption {
            type = lib.types.numbers.nonnegative;
            default = 90;
            description = "Total wall-clock budget for retrying the 07:00 acquire before giving up and alerting.";
          };
          baseSeconds = lib.mkOption {
            type = lib.types.numbers.nonnegative;
            default = 1.5;
            description = "Decorrelated-jitter floor between attempts.";
          };
          maxBackoffSeconds = lib.mkOption {
            type = lib.types.numbers.nonnegative;
            default = 15;
            description = "Cap on any single backoff sleep.";
          };
          maxRetryAfterSeconds = lib.mkOption {
            type = lib.types.numbers.nonnegative;
            default = 30;
            description = "Cap on an honoured server Retry-After, so a bogus value cannot stall the run.";
          };
        };
        secretsFile = lib.mkOption {
          type = lib.types.path;
          description = ''
            JSON with the private half of the config, wired by aqua-booking-secret:
            username, password, facilityId, gymName, and schedule (an attrset of
            lowercase weekday to local HH:MM). Kept out of the store because a gym
            and a weekly timetable say where someone is and when.
          '';
        };
      };

      config = {
        environment.systemPackages = [ dryRun ];

        systemd = {
          services = {
            aqua-booking = {
              description = "Book ${cfg.className} classes";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              environment = runEnvironment;

              unitConfig.OnFailure = "alert-failure@aqua-booking.service";
              # A once-daily oneshot with no Restart=; the start rate limit would only
              # ever block a legitimate manual retry or a timer/manual overlap.
              startLimitIntervalSec = 0;

              serviceConfig = runServiceConfig // {
                ExecStart = start;
              };
            };

            # Manual entrypoint: same credentials and hardening, but discovery only.
            # It still authenticates, so it also proves the stored refresh token works.
            aqua-booking-dry-run = {
              description = "Show what ${cfg.className} booking would do, without booking";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              environment = runEnvironment;
              # Run by hand, often several times in a row; no rate limit to trip over.
              startLimitIntervalSec = 0;

              serviceConfig = runServiceConfig // {
                ExecStart = "${start} --dry-run";
              };
            };

            # Dead-man's switch: OnFailure only fires when a run *fails*. A timer that
            # never triggers (host off at 07:00, systemd wedged) books nothing and says
            # nothing, so check the heartbeat the runner writes on every clean exit.
            # Alerts go to the default topic, not successTopicFile: a run that never
            # happened is an operational failure, not a booking outcome.
            aqua-booking-freshness = {
              description = "Alert if the daily ${cfg.className} booking run has not happened";
              # The watchdog itself must not fail silently.
              unitConfig.OnFailure = "alert-failure@aqua-booking-freshness.service";
              serviceConfig.Type = "oneshot";
              script = ''
                set -uo pipefail
                stamp=/var/lib/aqua-booking/last_run
                alert() {
                  ${lib.getExe config.blizzard.alerts.send} "${cfg.className} booking stale" "$1" 4 warning
                }
                if [ ! -e "$stamp" ]; then
                  alert "aqua-booking has never completed a run — check journalctl -u aqua-booking"
                  exit 0
                fi
                age=$(( $(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y "$stamp") ))
                # 24h: the 07:00 run plus an hour of slack before this 08:00 check.
                if [ "$age" -gt 86400 ]; then
                  alert "no completed booking run in $((age / 3600))h — the 07:00 timer did not fire"
                fi
              '';
            };
          };

          timers = {
            aqua-booking = {
              description = "Fire ${cfg.className} booking just after the 07:00 release";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* 07:00:05 Europe/London";
                # Jitter the hit off the exact release instant; AccuracySec must be
                # sub-minute or systemd quantizes the randomization away.
                RandomizedDelaySec = "6s";
                AccuracySec = "1s";
                # A late catch-up can still take a seat or a waitlist slot; nothing can't.
                Persistent = true;
              };
            };

            aqua-booking-freshness = {
              description = "Check that the ${cfg.className} booking run happened";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* 08:00 Europe/London";
                Persistent = true;
              };
            };
          };
        };
      };
    };
}
