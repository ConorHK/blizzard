{ config, ... }:
let
  inherit (config.flake.wrappers.git) install;
in
{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      imports = [ install ];
      wrappers.git.enable = true;

      home.packages = [
        pkgs.difftastic
        pkgs.git-absorb
        pkgs.pre-commit
      ];
    };
}
