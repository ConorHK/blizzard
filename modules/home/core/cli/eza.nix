{
  flake.modules.homeManager.core =
    { lib, pkgs, ... }:
    let
      ls = lib.concatStringsSep " " [
        "${pkgs.eza}/bin/eza"
        "--hyperlink=auto"
        "--group"
        "--icons"
        "--git"
        "--header"
        "--all"
      ];
    in
    {
      home.packages = [ pkgs.eza ];
      home.shellAliases = {
        inherit ls;
        l = "${ls} --long";
        la = "eza -a";
        ll = "eza -l";
        lla = "eza -la";
        lt = "${ls} --tree";
        tree = "${ls} --tree";
      };
    };
}
