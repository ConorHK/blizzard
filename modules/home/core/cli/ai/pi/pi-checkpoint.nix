topLevel: {
  perSystem =
    { pkgs, ... }:
    {
      packages.pi-checkpoint = pkgs.runCommand "pi-checkpoint" { } ''
        cp -r ${./checkpoint} $out
      '';
    };

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.pi.checkpoint.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the checkpoint and rewind tools.";
      };

      config = lib.mkIf config.programs.pi.checkpoint.enable {
        programs.pi.extensionDirs.checkpoint =
          topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-checkpoint;
      };
    };
}
