_: {
  # App exports on the phone reach this host by syncthing.
  flake.modules.nixos.backup-phone =
    { config, lib, ... }:
    let
      dir = "${config.services.syncthing.dataDir}/phone-backup";
    in
    {
      options.blizzard.backup.phoneDevice = lib.mkOption {
        type = lib.types.str;
        default = "banshee";
        description = "Syncthing device name of the phone.";
      };

      config = {
        assertions = [
          {
            assertion = config.services.syncthing.enable;
            message = "backup-phone needs services.syncthing; import syncthing-server.";
          }
        ];

        services.syncthing.settings.folders.phone-backup = {
          path = dir;
          devices = [ config.blizzard.backup.phoneDevice ];
          # Edits here never flow back to the phone.
          type = "receiveonly";
        };

        blizzard.backup.jobs.phone = {
          # Syncthing owns the folder.
          user = "root";
          # Clear of the 03:00 host backup.
          schedule = "01:30";
          paths = [ dir ];
          # Syncthing keeps the phone's mtimes, so this dates the last export.
          freshPaths = [ dir ];
          # Some apps export only by hand.
          freshMaxAge = 14 * 24;
          exclude = [ "${dir}/.stfolder" ];
        };
      };
    };
}
