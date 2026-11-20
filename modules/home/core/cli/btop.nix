{ config, ... }:
{
  flake.modules.homeManager = {
    core = {
      imports = [ config.flake.wrappers.btop.install ];
      wrappers.btop.enable = true;
    };
    desktop =
      { pkgs, ... }:
      {
        wrappers.btop.package = pkgs.btop-rocm;
      };
  };
}
