{
  flake.modules.nixos.users =
    { lib, ... }:
    let
      keysFile = builtins.readFile (
        builtins.fetchurl {
          url = "https://github.com/conorhk.keys";
          sha256 = "0rfpraagbfpc8h3wiazd3snq931zd0mlsfpvwh6swph4d56vf4xl";
        }
      );
      keysList = builtins.filter (x: x != "") (lib.splitString "\n" keysFile);
    in
    {
      users.users.goose = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPassword = "$6$o/.qISAqaJ2DbFIA$sFd/J56LT46H4CVH6SYKVRIUmK.KaFeePMj0xdPYzCksDc9a1J1VAEQkGJ9jUarAV68GIriIyc94w7qvgHlIp1";
        home = "/home/goose";
        createHome = true;
        openssh.authorizedKeys.keys = keysList;
      };
    };
}
