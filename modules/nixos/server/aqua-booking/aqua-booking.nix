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
          "aqua_booking.notify"
          "aqua_booking.retry"
          "aqua_booking.run"
          "aqua_booking.store"
        ];
        meta.mainProgram = "aqua-booking";
      };

      configJson = (pkgs.formats.json { }).generate "aqua-booking.json" {
        inherit (cfg)
          facilityId
          gymName
          className
          timezone
          releaseHorizonDays
          schedule
          successTopic
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
          scope = "openid offline_access https://mynuffield.onmicrosoft.com/BookingAPIM/booking_api_access";
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

      successTopicFile = pkgs.writeText "aqua-success-topic" "NTFY_TOPIC=${cfg.successTopic}\n";

      start = pkgs.writeShellScript "aqua-booking-start" ''
        exec ${lib.getExe app} \
          --config ${configJson} \
          --credentials "$CREDENTIALS_DIRECTORY/credentials"
      '';
    in
    {
      options.blizzard.aqua-booking = {
        facilityId = lib.mkOption {
          type = lib.types.str;
          default = "a2T4J000001JJfnUAG";
          description = "Salesforce facility ID of the gym (Crawley).";
        };
        gymName = lib.mkOption {
          type = lib.types.str;
          default = "Crawley";
        };
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
          default = 7;
          description = "Days ahead a class opens at 07:00. Measured 7; the user recalled 8.";
        };
        schedule = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {
            monday = "11:15";
            tuesday = "09:30";
            wednesday = "14:00";
            thursday = "10:45";
            friday = "14:00";
          };
          description = "Local (Europe/London) start time to book per weekday.";
        };
        successTopic = lib.mkOption {
          type = lib.types.str;
          default = "test-notification";
          description = "ntfy topic for booking confirmations.";
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
        credentialsFile = lib.mkOption {
          type = lib.types.path;
          description = "File with NUFFIELD_USERNAME= and NUFFIELD_PASSWORD= lines; wired by aqua-booking-secret.";
        };
      };

      config = {
        systemd.services.aqua-booking = {
          description = "Book ${cfg.className} classes at ${cfg.gymName}";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = {
            ALERT_SEND = lib.getExe config.blizzard.alerts.send;
            AQUA_SUCCESS_TOPIC_FILE = "${successTopicFile}";
            TZDIR = "${pkgs.tzdata}/share/zoneinfo";
          };

          unitConfig.OnFailure = "alert-failure@aqua-booking.service";
          # A once-daily oneshot with no Restart=; the start rate limit would only
          # ever block a legitimate manual retry or a timer/manual overlap.
          startLimitIntervalSec = 0;

          serviceConfig = {
            Type = "oneshot";
            ExecStart = start;
            LoadCredential = "credentials:${cfg.credentialsFile}";
            StateDirectory = "aqua-booking";
            WorkingDirectory = "/var/lib/aqua-booking";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        systemd.timers.aqua-booking = {
          description = "Fire ${cfg.className} booking just after the 07:00 release";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 07:00:05 Europe/London";
            # Jitter the hit off the exact release instant; AccuracySec must be
            # sub-minute or systemd quantizes the randomization away.
            RandomizedDelaySec = "35s";
            AccuracySec = "1s";
            Persistent = false;
          };
        };
      };
    };
}
