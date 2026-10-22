{
  flake.modules.nixos."nixosConfigurations/puca" = {
    age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMi3IuMov8gNVRZnhNe9A4ZdcqTU3MYs85rjkrZCasuP";

    networking.hostName = "puca";
    networking.ipv4.address = "192.168.0.165";

    # Rootful podman writes the config as root.
    restic.user = "root";

    system = {
      stateVersion = "25.05";
    };
  };
}
