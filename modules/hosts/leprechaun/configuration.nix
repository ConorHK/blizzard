{
  flake.modules.nixos."nixosConfigurations/leprechaun" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOwlNw/AL4VIXCrnUlllMVpWj/G0e82AuU3YbjcwtKQ1";

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

    system = {
      stateVersion = "25.05";
    };
  };
}
