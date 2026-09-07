{ inputs, ... }:
{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.zmx
        (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.zmx-open
      ];
    };
}
