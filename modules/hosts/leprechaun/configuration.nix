{
  flake.modules.nixos."nixosConfigurations/leprechaun" =
    { config, lib, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOwlNw/AL4VIXCrnUlllMVpWj/G0e82AuU3YbjcwtKQ1";

      restic = {
        repository = "s3:s3.us-east-005.backblazeb2.com/restic-backup-leprechaun";
        # Matches disko.nix.
        zfsDatasets = {
          "storage/data" = config.blizzard.storage.data;
          "storage/media" = config.blizzard.storage.media;
        };
      };

      blizzard = {
        bitbang.shareMembers = [ "driver" ];

        # Every host shares this token; check once.
        secretExpiry.secrets.github-nix = {
          file = config.age.secrets.github-nix-token.path;
          probe = config.blizzard.secretExpiry.probes.github;
        };

        # bananach cannot page while it is down.
        gatusWatch.url = "http://100.96.40.127:8080/health";

        # Old .lep names; drop once unused.
        nginx.redirects = lib.mapAttrs' (old: lib.nameValuePair "${old}.lep.goosebox.org") (
          lib.genAttrs [
            "autobrr"
            "budget"
            "changedetection"
            "lidarr"
            "photon"
            "photos"
            "slskd"
          ] (name: "${name}.goosebox.org")
          // {
            dawarich = "location.goosebox.org";
            glance = "news.goosebox.org";
            mealie = "recipes.goosebox.org";
          }
        );
      };

      boot = {
        supportedFilesystems = [ "zfs" ];
        zfs = {
          extraPools = [ "storage" ];
          forceImportRoot = false;
        };
      };

      networking = {
        hostName = "leprechaun";
        ipv4.address = "192.168.0.234";
        # head -c4 /dev/urandom | od -A none -t x4
        hostId = "748fda6c";
      };

      services = {
        sanoid = {
          enable = true;
          datasets."storage/data" = {
            autosnap = true;
            autoprune = true;
            hourly = 24;
            daily = 7;
            monthly = 3;
          };
        };

        # A single-disk pool can't self-heal, but scrub still surfaces silent
        # bitrot early — turning "restic restored a corrupt file" into advance warning.
        zfs.autoScrub = {
          enable = true;
          interval = "weekly";
        };
      };

      users.mutableUsers = false;

      nix = {
        gc = {
          automatic = lib.mkForce false;
          dates = lib.mkForce "daily";
        };
        settings = {
          eval-cores = lib.mkForce 2;
          max-jobs = lib.mkForce 2;
          cores = 2;
          min-free = lib.mkForce 10737418240; # 10 GB
          max-free = lib.mkForce 21474836480; # 20 GB
        };
      };

      # Default ARC ceiling is nearly all RAM.
      boot.kernelParams = [ "zfs.zfs_arc_max=3221225472" ]; # 3 GiB

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
