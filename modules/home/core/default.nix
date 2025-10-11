{
  flake.modules.homeManager.core =
    { lib, ... }:
    {
      home = {
        username = lib.mkDefault "goose";
        homeDirectory = lib.mkDefault "/home/goose";
      };
    };
}
