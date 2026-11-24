{ config, ... }:
{
  flake.modules.homeManager.core = {
    imports = [ config.flake.wrappers.bat.install ];
    wrappers.bat.enable = true;
  };
}
