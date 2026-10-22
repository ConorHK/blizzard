_: {
  flake.modules.nixos.restic-secrets =
    { config, ... }:
    let
      host = config.networking.hostName;
    in
    {
      age.secrets = {
        # Per host, so one leak exposes one repo.
        restic-password = {
          rekeyFile = ./secrets + "/${host}-password.age";
          owner = config.restic.user;
        };
        restic-ntfy-topic.rekeyFile = ./secrets/restic-ntfy-topic.age;
      };

      restic = {
        passwordFile = config.age.secrets.restic-password.path;
        ntfyTopicFile = config.age.secrets.restic-ntfy-topic.path;
      };
    };
}
