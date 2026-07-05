{
  flake.modules.nixos.server-users =
    {
      config,
      blizzardLib,
      lib,
      ...
    }:
    lib.mkMerge [
      (blizzardLib.mkUser {
        username = "driver";
        hashedPasswordFile = config.age.secrets.driver-password-hash.path;
        inherit (config.blizzard) sshKeys;
      })
      {
        age.secrets.driver-password-hash.rekeyFile = ./secrets/driver-password-hash.age;

        nix.settings.trusted-users = [ "driver" ];
        users.users.driver.extraGroups = [ "systemd-journal" ];
      }
    ];
}
