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
      pi-autoresearch = mkPiExtension pkgs "pi-autoresearch" { };
    in
    {
      options.programs.pi.autoresearch.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-autoresearch package.";
      };

      config = lib.mkIf config.programs.pi.autoresearch.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-autoresearch}" ];
      };
    };
}
