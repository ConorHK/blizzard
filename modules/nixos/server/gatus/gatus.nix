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
          alerting.ntfy = {
            topic = ''"$ENV{NTFY_TOPIC}"'';
            url = "https://ntfy.sh";
            default-alert = {
              enabled = true;
              failure-threshold = 2;
              success-threshold = 1;
            };
          };
          maintenance = {
            start = "05:40";
            duration = "35m";
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
