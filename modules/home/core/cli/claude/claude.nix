{ inputs, ... }:
{
  nixpkgs.allowedUnfreePackages = [ "claude-code" ];

  flake.modules.homeManager.claude =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Deterministic PreToolUse guard: a machine "no" for the hard rules in
      # auto mode (never git push; git commit only on ai-* branches).
      # writeShellApplication adds a build-time shellcheck pass and pins jq/git
      # on PATH. Deny-only — it can subtract permission but never grant it, so
      # built-in safety is intact.
      autoModeGuard = pkgs.writeShellApplication {
        name = "claude-auto-mode-guard";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
        ];
        text = builtins.readFile ./auto-mode-guard.sh;
      };
      # Statusline renderer (binary claude-statusline), wired to settings.statusLine
      # below. jq pinned on PATH; shellcheck runs at build.
      statusline = pkgs.writeShellApplication {
        name = "claude-statusline";
        runtimeInputs = [ pkgs.jq ];
        text = builtins.readFile ./statusline.sh;
      };
      # Model names are gateway-scoped, so they only apply alongside the base URL.
      apertureEnv = {
        ANTHROPIC_BASE_URL = "https://ai.goat-lionfish.ts.net";
        ANTHROPIC_DEFAULT_OPUS_MODEL = "anthropic-sub/claude-opus-5";
        ANTHROPIC_DEFAULT_SONNET_MODEL = "anthropic-sub/claude-sonnet-5";
        ANTHROPIC_DEFAULT_HAIKU_MODEL = "anthropic-sub/claude-haiku-4-5-20251001";
        ANTHROPIC_DEFAULT_FABLE_MODEL = "anthropic-sub/claude-fable-5";
      };
      settings = {
        alwaysThinkingEnabled = true;
        enabledPlugins = {
          "backpressured@lucasfcosta" = true;
        };
        env = {
          # Auto mode will not engage without this opt-in.
          CLAUDE_CODE_ENABLE_AUTO_MODE = "1";
        }
        // lib.optionalAttrs config.programs.claude-code.aperture.enable apertureEnv;
        extraKnownMarketplaces = {
          lucasfcosta = {
            source = {
              path = "${inputs.backpressured}";
              source = "directory";
            };
          };
        };
        includeCoAuthoredBy = false;
        # Hard guardrails for auto mode, enforced deterministically (not via the
        # classifier, which is probabilistic). The guard no-ops unless
        # permission_mode == "auto", so interactive modes are unaffected.
        hooks = {
          PreToolUse = [
            {
              matcher = "Bash";
              hooks = [
                {
                  type = "command";
                  command = "${autoModeGuard}/bin/claude-auto-mode-guard";
                }
              ];
            }
          ];
        };
        modelReasoningEffort = "xhigh";
        statusLine = {
          type = "command";
          command = "${statusline}/bin/claude-statusline";
        };
        # "fullscreen" = flicker-free alt-screen renderer with virtualized
        # scrollback (equivalent to CLAUDE_CODE_NO_FLICKER=1).
        tui = "fullscreen";
        theme = "dark-ansi";
        permissions = {
          # Start every session in auto mode. Honored because this writes to the
          # USER settings file (~/.claude/settings.json); ignored from project/local scopes.
          defaultMode = "auto";
          allow = [
            # Built-in read tools
            "Read"
            "Grep"
            "Glob"
            "NotebookRead"
            # Web reads
            "WebFetch"
            "WebSearch"
          ];
        };
      };
      settingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);

      # Global instructions loaded into every session. Claude Code auto-reads
      # every ~/.claude/rules/*.md as user-scope memory; the other files there
      # are not repo-managed, so these are installed by the activation script
      # below to keep them declarative.
      engineeringStandards = ./engineering-standards-do-not-delete.md;
      writingStyle = ./writing-style-do-not-delete.md;
    in
    {
      options.programs.claude-code.aperture.enable =
        lib.mkEnableOption "routing Claude Code through the Aperture gateway";

      config.home.packages = [ pkgs.claude-code ];

      config.home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run install -Dm644 ${settingsFile} ${config.home.homeDirectory}/.claude/settings.json
        run install -Dm644 ${engineeringStandards} ${config.home.homeDirectory}/.claude/rules/engineering-standards-do-not-delete.md
        run install -Dm644 ${writingStyle} ${config.home.homeDirectory}/.claude/rules/writing-style-do-not-delete.md
        run install -Dm644 ${./skills/handoff/SKILL.md} ${config.home.homeDirectory}/.claude/skills/handoff/SKILL.md
        run install -Dm644 ${./skills/pickup/SKILL.md} ${config.home.homeDirectory}/.claude/skills/pickup/SKILL.md
      '';
    };

  flake.modules.nixos.claude = {
    nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
  };
}
