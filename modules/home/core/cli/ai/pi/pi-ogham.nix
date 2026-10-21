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
    {
      options.programs.pi.ogham.enable = lib.mkEnableOption "the ogham task tracker";

      config = lib.mkIf config.programs.pi.ogham.enable {
        programs.pi.extensionDirs.ogham =
          topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-ogham;
      };
    };
}
