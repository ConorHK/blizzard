_: {
  # Desktop home directories, one bucket per host.
  flake.modules.nixos.backup-home =
    { config, lib, ... }:
    let
      cfg = config.blizzard.backup.home;
      home = config.users.users.${cfg.user}.home;
    in
    {
      options.blizzard.backup.home.user = lib.mkOption {
        type = lib.types.str;
        default = "goose";
        description = "User whose home is backed up.";
      };

      config = {
        # Drop files here to have them backed up.
        systemd.tmpfiles.rules = [ "d ${home}/backup 0700 ${cfg.user} ${cfg.user} -" ];

        blizzard.backup.jobs.home = {
          bucket = "restic-backup-${config.networking.hostName}";
          # Reads owner-only key dirs.
          user = "root";
          paths = map (dir: "${home}/${dir}") [
            ".ssh"
            ".gnupg"
            "docs"
            "media"
            "backup"
          ];
          exclude = [
            "${home}/media/games"
            # Live agent sockets.
            "${home}/.gnupg/S.*"
          ];
          # Often off for days; Persistent runs it at boot.
          freshness = false;
        };
      };
    };
}
