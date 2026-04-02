_: {
  flake.lib.mkDisko =
    {
      device ? "/dev/nvme0n1",
      swapSize ? "8G",
      fido2 ? false,
    }:
    {
      disko.devices.disk.main = {
        type = "disk";
        inherit device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              label = "boot";
              name = "ESP";
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
              };
            };
            luks = {
              size = "100%";
              label = "luks";
              content = {
                type = "luks";
                name = "cryptroot";
                settings = {
                  allowDiscards = true;
                }
                // (
                  if fido2 then
                    {
                      crypttabExtraOpts = [
                        "fido2-device=auto"
                        "token-timeout=10"
                      ];
                    }
                  else
                    { }
                );
                extraOpenArgs = [
                  "--perf-no_read_workqueue"
                  "--perf-no_write_workqueue"
                ];
                content = {
                  type = "btrfs";
                  extraArgs = [
                    "-L"
                    "nixos"
                    "-f"
                  ];
                  subvolumes =
                    let
                      mountOptions = [
                        "compress=zstd"
                        "noatime"
                      ];
                    in
                    {
                      "/root" = {
                        mountpoint = "/";
                        mountOptions = [ "subvol=root" ] ++ mountOptions;
                      };
                      "/home" = {
                        mountpoint = "/home";
                        mountOptions = [ "subvol=home" ] ++ mountOptions;
                      };
                      "/persist" = {
                        mountpoint = "/persist";
                        mountOptions = [ "subvol=persist" ] ++ mountOptions;
                      };
                      "/log" = {
                        mountpoint = "/var/log";
                        mountOptions = [ "subvol=log" ] ++ mountOptions;
                      };
                      "/nix" = {
                        mountpoint = "/nix";
                        mountOptions = [ "subvol=nix" ] ++ mountOptions;
                      };
                      "/swap" = {
                        mountpoint = "/.swapvol";
                        swap.swapfile.size = swapSize;
                      };
                    };
                };
              };
            };
          };
        };
      };
    };
}
