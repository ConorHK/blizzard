{
  flake.modules.homeManager.core =
    { lib, pkgs, ... }:
    let
      ls = lib.concatStringsSep " " [
        "${pkgs.eza}/bin/eza"
        "--group"
        "--icons"
        "--git"
        "--header"
        "--all"
      ];
    in
    {
      programs.eza.enable = true;
      home.shellAliases = {
        inherit ls;
        l = "${ls} --long";
        lt = "${ls} --tree";
        tree = "${ls} --tree";
      };
    };
}
