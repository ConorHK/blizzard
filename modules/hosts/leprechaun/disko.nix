{
  flake.modules.nixos."nixosConfigurations/leprechaun" = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "512M";
                type = "EF00";
                priority = 1;
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };

        # Data drive — ZFS for easy future RAID expansion
        storage = {
          type = "disk";
          device = "/dev/sdb";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "storage";
                };
              };
            };
          };
        };

      };

      zpool = {
        storage = {
          type = "zpool";
          # No `mode` set = single disk for now; add mirror/raidz later
          options = {
            ashift = "12"; # 4K sector alignment, good for modern HDDs
          };
          rootFsOptions = {
            compression = "zstd";
            atime = "off";
          };
          datasets = {
            "data" = {
              type = "zfs_fs";
              options.mountpoint = "/storage/data";
            };
            "media" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/storage/media";
                compression = "off"; # media files are already compressed
              };
            };
          };
        };
      };

    };
  };
}
