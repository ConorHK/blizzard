_: {
  flake.modules.nixos.gatus =
    {
      config,
      lib,
      monitoringChecks,
      ...
    }:
    {
      age.secrets.gatus-ntfy-topic = {
        rekeyFile = ./secrets/gatus-ntfy-topic.age;
      };

      services.gatus = {
        enable = true;
        environmentFile = config.age.secrets.gatus-ntfy-topic.path;
        settings = {
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
          };

          alerting.ntfy = {
            topic = "$NTFY_TOPIC";
            url = "https://ntfy.sh";
            default-alert = {
              enabled = true;
              failure-threshold = 2;
              success-threshold = 1;
            };
          };
          # The autoUpgrade reboot only — this silences every endpoint, so
          # service-specific blips belong in that check's `maintenanceWindows`.
          maintenance = {
            start = "06:00";
            duration = "70m";
            timezone = "Europe/Dublin";
          };

          endpoints = map (
            check:
            {
              inherit (check)
                name
                url
                interval
                conditions
                ;
              alerts = [ { type = "ntfy"; } ];
            }
            // lib.optionalAttrs (check.timeout != null) {
              client.timeout = check.timeout;
            }
            // lib.optionalAttrs (check.maintenanceWindows != [ ]) {
              maintenance-windows = map (
                window:
                {
                  inherit (window) start duration timezone;
                }
                // lib.optionalAttrs (window.every != [ ]) { inherit (window) every; }
              ) check.maintenanceWindows;
            }
          ) monitoringChecks;
        };
      };
    };
}
