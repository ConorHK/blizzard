{ config, ... }:
{
  flake.modules.homeManager.core = {
    imports = [ config.flake.wrappers.ripgrep.install ];
    wrappers.ripgrep.enable = true;
  };
}
