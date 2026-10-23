_: {
  # Backblaze B2 backend, via its S3 API.
  flake.modules.nixos.backup-b2 =
    { lib, ... }:
    {
      options.blizzard.backup.jobs = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              # Region is per account, not per bucket.
              repository = lib.mkDefault "s3:s3.us-east-005.backblazeb2.com/${config.bucket}";
            }
          )
        );
      };
    };
}
