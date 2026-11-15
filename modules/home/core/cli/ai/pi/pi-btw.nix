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
      pi-btw = mkPiExtension pkgs "pi-btw" { };
    in
    {
      # Package entry: loads manifest extensions and skills.
      programs.pi.settings.packages = [ "${pi-btw}" ];
    };
}
