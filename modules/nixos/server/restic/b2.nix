_: {
  # Backblaze B2 backend, via its S3 API.
  flake.modules.nixos.restic-b2 =
    { config, ... }:
    let
      cfg = config.restic;
    in
    {
      # Bucket-scoped key: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
      age.secrets.restic-env = {
        rekeyFile = ./secrets + "/${config.networking.hostName}-b2.age";
        owner = cfg.user;
      };

      restic = {
        # Region is per account, not per bucket.
        repository = "s3:s3.us-east-005.backblazeb2.com/${cfg.bucket}";
        environmentFile = config.age.secrets.restic-env.path;
      };
    };
}
