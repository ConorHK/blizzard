{
  flake.modules.nixos.server-users =
    { config, ... }:
    {
      nix.settings = {
        trusted-users = [ "driver" ];
        builders-use-substitutes = true;
      };

      users.users.driver = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPassword = "$6$o/.qISAqaJ2DbFIA$sFd/J56LT46H4CVH6SYKVRIUmK.KaFeePMj0xdPYzCksDc9a1J1VAEQkGJ9jUarAV68GIriIyc94w7qvgHlIp1";
        home = "/home/driver";
        createHome = true;
        openssh.authorizedKeys.keys = config.blizzard.sshKeys;
      };
    };
}
