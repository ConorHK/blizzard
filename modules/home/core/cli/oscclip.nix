{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.oscclip ];
    };
}
