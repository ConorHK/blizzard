_: {
  # Shared by every host; repo secrets live in host config.
  flake.modules.nixos.backup-secrets =
    { config, ... }:
    {
      age.secrets.restic-ntfy-topic.rekeyFile = ./secrets/restic-ntfy-topic.age;

      blizzard.backup.ntfyTopicFile = config.age.secrets.restic-ntfy-topic.path;
    };
}
