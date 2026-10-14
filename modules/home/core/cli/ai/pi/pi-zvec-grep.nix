{ inputs, config, ... }:
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
      pi-zvec-grep = mkPiExtension pkgs "@luminascale/pi-zvec-grep" { };
    in
    {
      options.programs.pi.zvecGrep.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the zvec-grep extension.";
      };

      config = lib.mkIf config.programs.pi.zvecGrep.enable {
        programs.pi.extensionDirs.zvec-grep = pi-zvec-grep;

        # zg must be on PATH; the extension shells out to it.
        home.packages = [
          (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.zvec-grep
        ];
      };
    };
}
