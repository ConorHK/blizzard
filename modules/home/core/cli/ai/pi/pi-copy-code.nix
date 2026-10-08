topLevel: {
  perSystem =
    { pkgs, ... }:
    {
      packages.pi-copy-code = pkgs.runCommand "pi-copy-code" { } ''
        cp -r ${./copy-code} $out
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
      options.programs.pi.copyCode.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install /copy-code, which copies snippets unwrapped.";
      };

      config = lib.mkIf config.programs.pi.copyCode.enable {
        programs.pi.extensionDirs.copy-code =
          topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pi-copy-code;
      };
    };
}
