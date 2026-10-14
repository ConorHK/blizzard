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
      # Node pi needs native better-sqlite3.
      sqlitePrebuild =
        {
          x86_64-linux = "linux-x64";
          aarch64-linux = "linux-arm64";
          aarch64-darwin = "darwin-arm64";
          x86_64-darwin = "darwin-x64";
        }
        .${pkgs.stdenv.hostPlatform.system};
      pi-hermes-memory = mkPiExtension pkgs "pi-hermes-memory" {
        inherit (pkgs) stdenv;
        # Headers for source builds only.
        prune = [ "node-addon-api" ];
        # Mach-O prebuilds need no interpreter rewriting, and autoPatchelfHook
        # does not run on darwin.
        nativeBuildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
        buildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.stdenv.cc.cc.lib;
        dontStrip = true;
        postInstall = ''
          (
            cd $out/node_modules/better-sqlite3
            # N-API prebuild: any node major loads it.
            rm -rf deps src binding.gyp
            find prebuilds -type f ! -name '${sqlitePrebuild}.node' -delete
          )
          rm -rf $out/docs
        '';
      };
    in
    {
      options.programs.pi.hermesMemory.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the hermes-memory extension.";
      };

      config = lib.mkIf config.programs.pi.hermesMemory.enable {
        programs.pi.extensionDirs.hermes-memory = pi-hermes-memory;
      };
    };
}
