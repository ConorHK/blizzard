{ ... }:
let
  flake.modules.nixos.beeper.imports = [
    beeper
  ];
  beeper =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.beeper
      ];
    };
in
{
  nixpkgs.allowedUnfreePackages = [
    "beeper"
  ];
  inherit flake;
}
