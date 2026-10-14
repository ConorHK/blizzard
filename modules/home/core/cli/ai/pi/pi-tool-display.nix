{ config, ... }:
let
  inherit (config.flake.lib) mkPiExtension;
in
{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pi-tool-display = mkPiExtension pkgs "pi-tool-display" { };
    in
    {
      options.programs.pi.toolDisplay.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the tool-display extension.";
      };

      config = lib.mkIf config.programs.pi.toolDisplay.enable {
        programs.pi.extensionDirs.tool-display = pi-tool-display;
      };
    };
}
