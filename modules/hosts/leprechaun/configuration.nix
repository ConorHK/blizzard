{
  flake.modules.nixos."nixosConfigurations/leprechaun" =
    { lib, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOwlNw/AL4VIXCrnUlllMVpWj/G0e82AuU3YbjcwtKQ1";

      restic.repository = "s3:s3.us-east-005.backblazeb2.com/restic-backup-leprechaun";

      boot.supportedFilesystems = [ "zfs" ];
      boot.zfs.extraPools = [ "storage" ];
      networking = {
        hostName = "leprechaun";
        ipv4.address = "192.168.0.145";
        # head -c4 /dev/urandom | od -A none -t x4
        hostId = "748fda6c";
      };

      services.sanoid.datasets."storage/data" = {
        autosnap = true;
        autoprune = true;
        hourly = 24;
        daily = 7;
        monthly = 3;
      };

      users.mutableUsers = false;

      nix = {
        gc = {
          automatic = lib.mkForce false;
          dates = lib.mkForce "daily";
        };
        settings = {
          min-free = lib.mkForce 10737418240; # 10 GB
          max-free = lib.mkForce 21474836480; # 20 GB
          trusted-users = [ "github-runner-blizzard" ];
        };
      };

      programs.nh = {
        enable = true;
        clean = {
          enable = true;
          dates = "daily";
          extraArgs = "--keep 3";
        };
      };

      system = {
        stateVersion = "25.05";
      };
    };
}
