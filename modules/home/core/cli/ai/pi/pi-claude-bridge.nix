{ config, ... }:
let
  inherit (config.flake.lib) mkPiExtension;
in
{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.pi.claudeBridge;
      settingsFormat = pkgs.formats.json { };
      pi-claude-bridge = mkPiExtension pkgs "pi-claude-bridge" {
        # pkgs.claude-code replaces the bundled binary.
        prune = map (platform: "@anthropic-ai/claude-agent-sdk-${platform}") [
          "darwin-arm64"
          "darwin-x64"
          "linux-arm64"
          "linux-arm64-musl"
          "linux-x64"
          "linux-x64-musl"
          "win32-arm64"
          "win32-x64"
        ];
      };
      settingsFile = settingsFormat.generate "claude-bridge.json" cfg.settings;
    in
    {
      options.programs.pi.claudeBridge = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Install pi-claude-bridge, Claude Code as a provider.";
        };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "Contents of ~/.pi/agent/claude-bridge.json.";
        };
      };

      config = lib.mkIf cfg.enable {
        programs.pi = {
          settings.packages = [ "${pi-claude-bridge}" ];
          claudeBridge.settings = {
            provider.pathToClaudeCodeExecutable = lib.getExe pkgs.claude-code;
            askClaude.enabled = lib.mkDefault false;
          };
          # Hermes cannot reach bridge models in-process.
          hermesMemory.settings = {
            childExtensionPaths = [ "${pi-claude-bridge}" ];
            reviewTransport = "subprocess";
          };
        };
        # Writable copy: the bridge records its startup notice.
        home.activation.piClaudeBridge = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run install -Dm644 ${settingsFile} ${config.home.homeDirectory}/.pi/agent/claude-bridge.json
        '';
      };
    };
}
