{ inputs, ... }:
{
  flake.modules.nixos.zmx =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.zmx
        (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.zmx-open
      ];
    };
}
