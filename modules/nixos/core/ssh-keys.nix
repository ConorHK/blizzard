{
  flake.modules.nixos.core =
    { lib, ... }:
    let
      keysFile = builtins.readFile (
        builtins.fetchurl {
          url = "https://github.com/conorhk.keys";
          sha256 = "0dsy8sv3xzvai7lh3im1vr91gymm7p0ngrdys720wcnzgla2a9wi";
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
