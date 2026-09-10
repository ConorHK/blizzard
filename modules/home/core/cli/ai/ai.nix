{ config, ... }:
let
  # Agent-agnostic instructions; each agent installs
  # them in its own format.
  rules = {
    engineering-standards = ./rules/engineering-standards.md;
    writing-style = ./rules/writing-style.md;
  };
in
{
  flake.modules.homeManager.ai = {
    imports = with config.flake.modules.homeManager; [
      claude
      pi
    ];
    programs = {
      claude-code.managedRules = rules;
      pi.rules = rules;
    };
  };
}
