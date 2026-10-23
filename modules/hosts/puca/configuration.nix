{
  flake.modules.nixos."nixosConfigurations/puca" =
    { config, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMi3IuMov8gNVRZnhNe9A4ZdcqTU3MYs85rjkrZCasuP";

      networking.hostName = "puca";
      networking.ipv4.address = "192.168.0.165";

      age.secrets = {
        restic-password.rekeyFile = ./secrets/restic-password.age;
        # B2 key scoped to the bucket.
        restic-env.rekeyFile = ./secrets/restic-env.age;
      };

      blizzard.backup.jobs.service-data = {
        # Rootful podman writes the config as root.
        user = "root";
        passwordFile = config.age.secrets.restic-password.path;
        environmentFile = config.age.secrets.restic-env.path;
      };

      system = {
        stateVersion = "25.05";
      };
    };
}
