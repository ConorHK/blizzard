_: {
  flake.modules.nixos.alerts-secret =
    { config, ... }:
    {
      age.secrets.alert-ntfy-topic.rekeyFile = ./secrets/alert-ntfy-topic.age;
      blizzard.alerts.topicFile = config.age.secrets.alert-ntfy-topic.path;
    };
}
