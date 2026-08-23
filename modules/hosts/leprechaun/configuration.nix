{
  flake.modules.nixos."nixosConfigurations/leprechaun" =
    { lib, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOwlNw/AL4VIXCrnUlllMVpWj/G0e82AuU3YbjcwtKQ1";

      restic.repository = "s3:s3.us-east-005.backblazeb2.com/restic-backup-leprechaun";

      # gatus cannot usefully page about its own UI being down.
      blizzard.monitoring.exempt = [ "monitor.goosebox.org" ];

      services.nginx.virtualHosts."monitor.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://100.96.40.127:8080";
          proxyWebsockets = true;
        };
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
