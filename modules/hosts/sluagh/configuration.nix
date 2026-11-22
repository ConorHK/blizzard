{
  flake.modules.nixos."nixosConfigurations/sluagh" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPuwrX5tRwFbLUwm+x0WkJqjNsl3/O3phKXQM3Otyz1X";

    networking = {
      hostName = "sluagh";
      # head -c4 /dev/urandom | od -A none -t x4
      hostId = "3bf41414";
    };

    boot.supportedFilesystems = [ "zfs" ];

    services.zfs.autoScrub.enable = true;

    # 15G of RAM; leave the OS room.
    blizzard.ciRunner = {
      memoryHigh = "10G";
      memoryMax = "12G";
    };

    system.stateVersion = "26.11";
  };
}
