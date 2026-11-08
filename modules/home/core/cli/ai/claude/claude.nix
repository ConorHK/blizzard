{
  # pi-claude-bridge already allows claude-code as unfree.
  flake.modules.homeManager.claude =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      guard = pkgs.writeShellApplication {
        name = "claude-auto-mode-guard";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
        ];
        text = builtins.readFile ../auto-mode-guard.sh;
      };
      settings = {
        model = "claude-opus-5-5";
        effortLevel = "medium";
        includeCoAuthoredBy = false;
        # Auto mode will not engage without this opt-in.
        env.CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
        hooks.PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = lib.getExe guard;
              }
            ];
          }
        ];
        permissions = {
          defaultMode = "auto";
          allow = [
            "Read"
            "Grep"
            "Glob"
            "WebFetch"
            "WebSearch"
          ];
        };
      };
      settingsFile = (pkgs.formats.json { }).generate "claude-settings.json" settings;
      home = config.home.homeDirectory;
      # Claude Code reads every ~/.claude/rules/*.md as user memory.
      ruleInstalls = lib.mapAttrsToList (
        name: src: "run install -Dm644 ${src} ${home}/.claude/rules/${name}-do-not-delete.md"
      ) config.programs.pi.rules;
    in
    {
      home.packages = [ pkgs.claude-code ];

      # Writable copy: Claude Code rewrites settings.json.
      home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run install -Dm644 ${settingsFile} ${home}/.claude/settings.json
        ${lib.concatStringsSep "\n" ruleInstalls}
      '';
    };
}
