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
      pi-tool-display = mkPiExtension pkgs "pi-tool-display" { };
    in
    {
      programs.pi.extensionDirs.tool-display = pi-tool-display;
    };
}
