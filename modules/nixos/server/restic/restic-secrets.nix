_: {
  flake.modules.nixos.restic-secrets =
    { config, ... }:
    {
      age.secrets = {
        restic-password = {
          rekeyFile = ./secrets/restic-password.age;
          owner = "containers";
        };

        restic-env = {
          rekeyFile = ./secrets/restic-env.age;
          owner = "containers";
        };
        restic-ntfy-topic.rekeyFile = ./secrets/restic-ntfy-topic.age;
      };

      restic = {
        passwordFile = config.age.secrets.restic-password.path;
        environmentFile = config.age.secrets.restic-env.path;
        ntfyTopicFile = config.age.secrets.restic-ntfy-topic.path;
      };
    };
}
