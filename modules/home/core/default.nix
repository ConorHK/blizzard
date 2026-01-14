{
  flake.modules.homeManager.core =
    {
      lib,
      pkgs,
      ...
    }:
    {
      home = {
        username = lib.mkDefault "goose";
        homeDirectory = lib.mkDefault "/home/goose";
      };
      home.packages = [
        pkgs.serve-here
      ];
    };
}
