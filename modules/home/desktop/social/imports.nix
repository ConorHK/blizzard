{ config, ... }:
{
  flake.modules.homeManager.social.imports = with config.flake.modules.homeManager; [
    signal
  ];
}
