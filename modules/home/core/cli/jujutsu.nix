{ config, ... }:
{
  flake.modules.homeManager.jujutsu = {
    imports = [ config.flake.wrappers.jujutsu.install ];
    wrappers.jujutsu.enable = true;
  };
}
