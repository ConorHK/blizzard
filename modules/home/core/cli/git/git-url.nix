{ inputs, ... }:
{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home.packages = [
        (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.git-url
      ];
    };
}
