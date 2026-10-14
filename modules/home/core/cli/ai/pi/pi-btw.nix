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
      pi-btw = mkPiExtension pkgs "pi-btw" { };
    in
    {
      options.programs.pi.btw.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-btw package.";
      };

      config = lib.mkIf config.programs.pi.btw.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-btw}" ];
      };
    };
}
