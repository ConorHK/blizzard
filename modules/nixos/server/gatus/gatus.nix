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
          # Cover the 06:00 autoUpgrade + reboot window and the slowest service's
          # post-restart recovery (audiobookshelf's library scan) so it doesn't page.
          maintenance = {
            start = "06:00";
            duration = "120m";
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
