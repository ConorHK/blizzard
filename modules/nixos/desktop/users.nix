{
  flake.modules.nixos.users =
    {
      config,
      blizzardLib,
      lib,
      ...
    }:
    lib.mkMerge [
      { age.secrets.goose-password-hash.rekeyFile = ./secrets/goose-password-hash.age; }
      (blizzardLib.mkUser {
        username = "goose";
        hashedPasswordFile = config.age.secrets.goose-password-hash.path;
        inherit (config.blizzard) sshKeys;
      })
    ];
}
