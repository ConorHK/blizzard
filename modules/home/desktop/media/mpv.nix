{ config, ... }:
{
  flake.modules.homeManager.mpv = {
    imports = [ config.flake.wrappers.mpv.install ];
    wrappers.mpv.enable = true;
  };
}
