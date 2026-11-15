{ config, ... }:
let
  inherit (config.flake.lib) mkPiExtension;
in
{
  flake.modules.homeManager.pi =
    {
      pkgs,
      ...
    }:
    let
      pi-messenger = mkPiExtension pkgs "pi-messenger" { };
    in
    {
      # Package entry: loads manifest extensions and skills.
      programs.pi.settings.packages = [ "${pi-messenger}" ];
    };
}
