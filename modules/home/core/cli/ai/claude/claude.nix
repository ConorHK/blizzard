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
      cfg = config.programs.claude-code;
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
        text = builtins.readFile ../auto-mode-guard.sh;
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
        // lib.optionalAttrs cfg.aperture.enable apertureEnv;
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

      # Claude Code auto-reads every ~/.claude/rules/*.md as user-scope memory;
      # the other files there are not repo-managed, so rules are installed by
      # the activation script below to keep them declarative. The suffix warns
      # sessions off deleting deployed copies.
      ruleInstalls = lib.mapAttrsToList (
        name: src:
        "run install -Dm644 ${src} ${config.home.homeDirectory}/.claude/rules/${name}-do-not-delete.md"
      ) cfg.managedRules;
    in
    {
      options.programs.claude-code = {
        aperture.enable = lib.mkEnableOption "routing Claude Code through the Aperture gateway";
        # Upstream home-manager owns programs.claude-code.rules.
        managedRules = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          description = "Instruction files installed to ~/.claude/rules/<name>-do-not-delete.md.";
        };
      };

      config.home.packages = [ pkgs.claude-code ];

      config.home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run install -Dm644 ${settingsFile} ${config.home.homeDirectory}/.claude/settings.json
        ${lib.concatStringsSep "\n" ruleInstalls}
        run install -Dm644 ${./skills/handoff/SKILL.md} ${config.home.homeDirectory}/.claude/skills/handoff/SKILL.md
        run install -Dm644 ${./skills/pickup/SKILL.md} ${config.home.homeDirectory}/.claude/skills/pickup/SKILL.md
      '';
    };

  flake.modules.nixos.claude = {
    nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
  };
}
