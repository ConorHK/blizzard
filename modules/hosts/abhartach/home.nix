{ config, ... }:
{
  flake.modules.homeManager."homeConfigurations/abhartach" = {
    imports = with config.flake.modules.homeManager; [
      desktop
    ];
  };
}
