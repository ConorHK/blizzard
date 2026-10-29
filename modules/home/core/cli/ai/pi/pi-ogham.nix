topLevel: {
  perSystem =
    { pkgs, ... }:
    {
      packages.pi-ogham = pkgs.runCommand "pi-ogham" { } ''
        cp -r ${./ogham} $out
      '';
    };

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi.ogham;
      inherit (topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) pi-ogham zvec-grep;
      settingsFormat = pkgs.formats.json { };
    in
    {
      options.programs.pi.ogham = {
        enable = lib.mkEnableOption "the ogham task tracker";
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          example = {
            model = "anthropic/claude-haiku-4-5";
            winGuidance = "Tie each win to a team goal.";
          };
          description = "Contents of ~/.pi/agent/ogham.json: curator model, curate, winGuidance, askOnStart.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi.extensionDirs.ogham = pi-ogham;
        home.file.".pi/agent/ogham.json".source = settingsFormat.generate "pi-ogham.json" (
          { zg = lib.getExe' zvec-grep "zg"; } // cfg.settings
        );
      };
    };
}
