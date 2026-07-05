_: {
  flake.modules.nixos.gatus =
    { config, monitoringChecks, ... }:
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
          # Cover the whole autoUpgrade reboot window (06:00-07:00) so host
          # reboots don't page.
          maintenance = {
            start = "06:00";
            duration = "70m";
            timezone = "Europe/Dublin";
          };

          endpoints = map (check: {
            inherit (check)
              name
              url
              interval
              conditions
              ;
            alerts = [ { type = "ntfy"; } ];
          }) monitoringChecks;
        };
      };
    };
}
