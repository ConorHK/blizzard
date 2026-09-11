{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Pure TS source; only pi-bundled peer deps,
      # so the npm tarball needs no npm build.
      pi-tool-display = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-tool-display";
        version = "0.5.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-tool-display/-/pi-tool-display-${version}.tgz";
          hash = "sha256-7BvZF+TpkSH+RTklzg83fQNdCcQa6tp5bSimN1sw1no=";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.toolDisplay.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the tool-display extension.";
      };

      config = lib.mkIf config.programs.pi.toolDisplay.enable {
        programs.pi.extensionDirs.tool-display = pi-tool-display;
      };
    };
}
