{
  flake.modules.nixos."nixosConfigurations/puca" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMi3IuMov8gNVRZnhNe9A4ZdcqTU3MYs85rjkrZCasuP";

    restic.repository = "s3:s3.us-east-005.backblazeb2.com/restic-backup-leprechaun/puca";

    networking.hostName = "puca";
    networking.ipv4.address = "192.168.0.165";

    system = {
      stateVersion = "25.05";
    };
  };
}
