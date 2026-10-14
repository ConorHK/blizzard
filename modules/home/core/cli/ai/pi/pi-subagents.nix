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
      pi-subagents = mkPiExtension pkgs "pi-subagents" { };
    in
    {
      options.programs.pi.subagents.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-subagents package.";
      };

      config = lib.mkIf config.programs.pi.subagents.enable {
        # Package entry: loads manifest extensions, skills, prompts.
        programs.pi.settings.packages = [ "${pi-subagents}" ];
      };
    };
}
