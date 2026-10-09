{ config, ... }:
let
  inherit (config.flake.modules.nixos) gatus-relay;
in
{
  flake.modules.nixos.gatus =
    {
      config,
      lib,
      monitoringChecks,
      ...
    }:
    {
      imports = [ gatus-relay ];

      age.secrets.gatus-ntfy-topic = {
        rekeyFile = ./secrets/gatus-ntfy-topic.age;
      };
      blizzard.gatusRelay.topicFile = config.age.secrets.gatus-ntfy-topic.path;

      # Nothing else watches the watcher.
      systemd.services.gatus.unitConfig.OnFailure = "alert-failure@gatus.service";

      services.gatus = {
        enable = true;
        settings = {
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
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
              alerts = [ { type = "custom"; } ];
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
