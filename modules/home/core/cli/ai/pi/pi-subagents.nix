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
      pi-subagents = mkPiExtension pkgs "pi-subagents" { };
    in
    {
      # Package entry: loads manifest extensions, skills, prompts.
      programs.pi.settings.packages = [ "${pi-subagents}" ];
    };
}
