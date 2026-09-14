_: {
  flake.modules.nixos.storage =
    { lib, ... }:
    {
      options.blizzard.storage = {
        data = lib.mkOption {
          type = lib.types.path;
          default = "/storage/data";
          description = "Root for service state directories.";
        };

        media = lib.mkOption {
          type = lib.types.path;
          default = "/storage/media";
          description = "Root for media libraries.";
        };

        matrix = lib.mkOption {
          type = lib.types.path;
          default = "/storage/matrix";
          description = "Root for Matrix homeserver state.";
        };

        home-assistant = lib.mkOption {
          type = lib.types.path;
          default = "/home/driver/storage/homeassistant";
          description = "Directory holding Home Assistant config.";
        };
      };
    };
}
