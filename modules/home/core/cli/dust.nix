{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home = {
        packages = [ pkgs.du-dust ];
        shellAliases.du = "dust";
      };
    };
}
