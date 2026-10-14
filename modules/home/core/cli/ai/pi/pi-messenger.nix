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
      pi-messenger = mkPiExtension pkgs "pi-messenger" { };
    in
    {
      options.programs.pi.messenger.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-messenger package.";
      };

      config = lib.mkIf config.programs.pi.messenger.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-messenger}" ];
      };
    };
}
