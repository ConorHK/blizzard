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

        photos = lib.mkOption {
          type = lib.types.path;
          default = "/storage/photos";
          description = "Root for photo originals and their dumps.";
        };

        downloads = lib.mkOption {
          type = lib.types.path;
          default = "/storage/downloads";
          description = "Scratch space for downloads in progress.";
        };

        matrix = lib.mkOption {
          type = lib.types.path;
          default = "/storage/matrix";
          description = "Root for Matrix homeserver state.";
        };
      };
    };
}
