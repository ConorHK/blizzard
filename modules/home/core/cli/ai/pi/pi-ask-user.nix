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
      pi-ask-user = mkPiExtension pkgs "pi-ask-user" { };
    in
    {
      options.programs.pi.askUser = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install the pi-ask-user package.";
        };

        settings = lib.mkOption {
          inherit (pkgs.formats.json { }) type;
          # Overlays cannot draw over terminal images, so prompts render inline.
          default.displayMode = "inline";
          description = "Contents of ~/.pi/agent/ask-user.json.";
        };
      };

      config = lib.mkIf config.programs.pi.askUser.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-ask-user}" ];
        home.file.".pi/agent/ask-user.json".text = builtins.toJSON config.programs.pi.askUser.settings;
      };
    };
}
