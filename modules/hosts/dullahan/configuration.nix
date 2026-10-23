{
  flake.modules.nixos."nixosConfigurations/dullahan" =
    { config, ... }:
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILckflL1zKiJOTmgA3E7uhn7+Em+Nv940moIIaN3opbd";

      networking.hostName = "dullahan";
      networking.ipv4.address = "192.168.0.183";

      age.secrets = {
        home-backup-password = {
          rekeyFile = ./secrets/home-backup-password.age;
          generator.script = "alnum";
        };
        # B2 key scoped to the bucket.
        home-backup-b2.rekeyFile = ./secrets/home-backup-b2.age;
      };

      blizzard = {
        bitbang.shareMembers = [ "goose" ];
        backup.jobs.home = {
          passwordFile = config.age.secrets.home-backup-password.path;
          environmentFile = config.age.secrets.home-backup-b2.path;
        };
      };

      security.sudo.wheelNeedsPassword = false;

      system = {
        stateVersion = "25.05";
        autoUpgrade.enable = false;
      };
    };
}
