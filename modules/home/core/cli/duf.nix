{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home = {
        packages = [ pkgs.duf ];
        shellAliases.df = "duf";
      };
    };
}
