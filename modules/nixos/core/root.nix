{
  flake.modules.nixos.root =
    { config, lib, ... }:
    {
      services.userborn.enable = lib.mkDefault true;

      # Password hashes live in agenix rather than the repo: committed hashes
      # are an offline cracking target.
      age.secrets.root-password-hash.rekeyFile = ./secrets/root-password-hash.age;

      users = {
        mutableUsers = false;
        users.root = {
          isSystemUser = true;
          hashedPasswordFile = config.age.secrets.root-password-hash.path;
          openssh.authorizedKeys.keys = config.blizzard.sshKeys;
        };
      };
    };
}
