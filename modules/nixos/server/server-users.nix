{
  flake.modules.nixos.server-users =
    { lib, ... }:
    let
      keysFile = builtins.readFile (
        builtins.fetchurl {
          url = "https://github.com/conorhk.keys";
          sha256 = "0dcf44q55cqnsnkb4wls1blhzmykrla4kda9mf1v1yc6vpwqgsap";
        }
      );
      keysList = builtins.filter (x: x != "") (lib.splitString "\n" keysFile);
    in
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
        openssh.authorizedKeys.keys = keysList;
      };
    };
}
