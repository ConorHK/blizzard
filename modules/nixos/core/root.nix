{
  flake.modules.nixos.root =
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
      services.userborn.enable = true;
      users = {
        mutableUsers = false;
        users.root = {
          isSystemUser = true;
          hashedPassword = "$6$W1tE3/h9AFWOXaXi$pGpXeXFoE/Jyi2RzkuiTfr5dA6FQ.R6Mme8sxi5nWXLIrv7R9d5b0cDoqbb830MWkwwdKbGqBo6f3ZoIhCMjA0";
          openssh.authorizedKeys.keys = keysList;
        };
      };
    };
}
