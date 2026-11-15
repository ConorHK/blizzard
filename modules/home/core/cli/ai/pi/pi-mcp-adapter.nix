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
      pi-mcp-adapter = mkPiExtension pkgs "pi-mcp-adapter" {
        # recheck natives skipped: pure JS fallback.
        prune = [
          "recheck-jar"
          "recheck-linux-arm64"
          "recheck-linux-x64"
          "recheck-macos-arm64"
          "recheck-macos-x64"
          "recheck-windows-x64"
        ];
      };
    in
    {
      programs.pi.settings = {
        # Package entry: loads the manifest extension.
        packages = [ "${pi-mcp-adapter}" ];
        # The adapter replaces built-in MCP.
        extensions = [ "-builtin:mcp" ];
      };
    };
}
