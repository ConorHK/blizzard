{
  flake.modules.nixos.core =
    { lib, ... }:
    let
      keysFile = builtins.readFile (
        builtins.fetchurl {
          url = "https://github.com/conorhk.keys";
          sha256 = "0dcf44q55cqnsnkb4wls1blhzmykrla4kda9mf1v1yc6vpwqgsap";
        }
      );
    in
    {
      options.blizzard.sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = builtins.filter (x: x != "") (lib.splitString "\n" keysFile);
        description = "SSH public keys fetched from GitHub";
      };
    };
}
