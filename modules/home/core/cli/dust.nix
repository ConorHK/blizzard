{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home = {
        packages = [ pkgs.dust ];
        shellAliases.du = "dust";
      };
    };
}
