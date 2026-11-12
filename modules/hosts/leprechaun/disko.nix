{
  flake.modules.nixos."nixosConfigurations/leprechaun" = {
    disko.devices = {
      disk = {
        main = {
          type = "disk";
          device = "/dev/disk/by-id/ata-Samsung_SSD_850_EVO_250GB_S2R6NX0H614151A";
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

        storage = {
          type = "disk";
          device = "/dev/disk/by-id/ata-TOSHIBA_MG09ACA18TE_3430A0LNFJDH";
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

        fast = {
          type = "disk";
          device = "/dev/disk/by-id/nvme-Sabrent_288E07051A5302035881";
          content = {
            type = "gpt";
            partitions = {
              data = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "fast";
                };
              };
            };
          };
        };
      };

      zpool = {
        storage = {
          type = "zpool";
          options = {
            ashift = "12"; # 4K sector alignment, good for modern HDDs
          };
          rootFsOptions = {
            compression = "zstd";
            atime = "off";
          };
          datasets = {
            "photos" = {
              type = "zfs_fs";
              options.mountpoint = "/storage/photos";
            };
            # Nightly syncoid copies of the fast pool.
            "replica" = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                canmount = "off";
              };
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

        fast = {
          type = "zpool";
          options.ashift = "12";
          rootFsOptions = {
            compression = "zstd";
            atime = "off";
            mountpoint = "none";
          };
          datasets = {
            "data" = {
              type = "zfs_fs";
              options.mountpoint = "/storage/data";
            };
            # Capped so a large torrent cannot starve the databases.
            "downloads" = {
              type = "zfs_fs";
              options = {
                mountpoint = "/storage/downloads";
                quota = "150G";
                compression = "off";
              };
            };
          };
        };
      };

    };
  };
}
