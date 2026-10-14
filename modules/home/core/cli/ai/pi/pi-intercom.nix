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
      pi-intercom = mkPiExtension pkgs "pi-intercom" {
        # Node strips types; broker needs no tsx.
        prune = [ "tsx" ];
        postInstall = ''
          substituteInPlace $out/config.ts \
            --replace-fail 'brokerCommand: "npx",' 'brokerCommand: "${lib.getExe' pkgs.nodejs-slim "node"}",' \
            --replace-fail 'brokerArgs: ["--no-install", "tsx"],' 'brokerArgs: [],'
        '';
      };
    in
    {
      options.programs.pi.intercom.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-intercom package.";
      };

      config = lib.mkIf config.programs.pi.intercom.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-intercom}" ];
      };
    };
}
