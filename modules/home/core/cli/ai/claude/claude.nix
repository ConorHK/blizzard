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
      # Labels the herdr-core terminal with the session, so herdr-resume can reopen it.
      hcSession = pkgs.writeShellApplication {
        name = "claude-hc-session";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          [ -n "''${HC_TERMINAL_ID:-}" ] && command -v hc >/dev/null || exit 0
          session=$(jq -r '.session_id // empty')
          [ -n "$session" ] || exit 0
          # SessionStart stdout lands in the model's context, so keep it quiet.
          hc label "$HC_TERMINAL_ID" "claude.session=$session" >/dev/null 2>&1 || true
        '';
      };
      worktree = pkgs.writeShellApplication {
        name = "claude-worktree";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
        ];
        text = builtins.readFile ./worktree.sh;
      };
      worktreeHook = event: [
        {
          hooks = [
            {
              type = "command";
              command = "${lib.getExe worktree} ${event}";
            }
          ];
        }
      ];
      settings = {
        model = "claude-opus-5-5";
        effortLevel = "medium";
        includeCoAuthoredBy = false;
        tui = "fullscreen";
        env = {
          # Auto mode will not engage without this opt-in.
          CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
          CLAUDE_CODE_PLUGIN_DIRS = "${./sudo-ssh}";
        };
        hooks = {
          SessionStart = [
            {
              hooks = [
                {
                  type = "command";
                  command = lib.getExe hcSession;
                }
              ];
            }
          ];
          WorktreeCreate = worktreeHook "create";
          WorktreeRemove = worktreeHook "remove";
        };
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
