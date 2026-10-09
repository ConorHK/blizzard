{ config, lib, ... }:
let
  # Agent-agnostic instructions; each agent installs
  # them in its own format.
  rules = {
    adhd-output = ./rules/adhd-output.md;
    engineering-standards = ./rules/engineering-standards.md;
    writing-style = ./rules/writing-style.md;
  };
in
{
  flake.modules.homeManager.ai = {
    imports = [ config.flake.modules.homeManager.pi ];
    programs.pi = {
      inherit rules;
      settings = lib.mapAttrs (_: lib.mkDefault) {
        defaultProvider = "claude-bridge";
        defaultModel = "claude-opus-5-5";
        defaultThinkingLevel = "medium";
      };
      advisor.settings.model = lib.mkDefault "claude-bridge/claude-sonnet-5-5";
    };
  };
}
