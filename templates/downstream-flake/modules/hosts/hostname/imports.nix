{ inputs, ... }:
{
  homeConfigurations."hostname" = {
    unstable = true;
    username = "username";
    homeDirectory = "/home/username";
  };
  imports = [
    inputs.blizzard.flakeModules.homeConfigurations
  ];
}
