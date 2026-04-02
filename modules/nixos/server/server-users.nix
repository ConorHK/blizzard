{
  flake.modules.nixos.server-users =
    { config, blizzardLib, lib, ... }:
    lib.mkMerge [
      (blizzardLib.mkUser {
        username = "driver";
        hashedPassword = "$6$o/.qISAqaJ2DbFIA$sFd/J56LT46H4CVH6SYKVRIUmK.KaFeePMj0xdPYzCksDc9a1J1VAEQkGJ9jUarAV68GIriIyc94w7qvgHlIp1";
        inherit (config.blizzard) sshKeys;
      })
      {
        nix.settings.trusted-users = [ "driver" ];
        users.users.driver.extraGroups = [ "systemd-journal" ];
      }
    ];
}
