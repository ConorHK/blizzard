{
  flake.modules.nixos.core =
    { lib, blizzardLib, ... }:
    {
      options.blizzard.sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = blizzardLib.conorhkSshKeys;
        description = "SSH public keys fetched from GitHub";
      };
    };
}
