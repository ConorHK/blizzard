{
  flake.modules.nixos."nixosConfigurations/leprechaun" = {
    # age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMi3IuMov8gNVRZnhNe9A4ZdcqTU3MYs85rjkrZCasuP";

    networking = {
      hostName = "leprechaun";
      ipv4.address = "192.168.0.145";
      # head -c4 /dev/urandom | od -A none -t x4
      hostId = "748fda6c";
    };

    system = {
      stateVersion = "25.05";
    };
  };
}
