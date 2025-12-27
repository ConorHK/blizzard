{
  flake.modules.homeManager.core =
    {
      lib,
      inputs,
      pkgs,
      ...
    }:
    {
      home = {
        username = lib.mkDefault "goose";
        homeDirectory = lib.mkDefault "/home/goose";
      };
      home.packages = [
        inputs.self.packages.${pkgs.system}.serve-here
      ];
    };
}
