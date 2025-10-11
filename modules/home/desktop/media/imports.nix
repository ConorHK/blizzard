{ config, ... }:
{
  flake.modules.homeManager.media.imports = with config.flake.modules.homeManager; [
    gfx
    mpv
    spotify
    zathura
  ];
}
