{ inputs, ... }:
{
  # herdr-show: Claude Code draws in the canvas sidebar through the same file and label as pi's show_ui.
  flake.modules.homeManager.herdr =
    { lib, pkgs, ... }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-core;
      show =
        pkgs.writers.writePython3Bin "herdr-show"
          {
            libraries = [ pkgs.python3Packages.pillow ];
            flakeIgnore = [ "E501" ];
          }
          (
            builtins.replaceStrings [ "@hc@" ] [ (lib.getExe herdr-core) ] (
              builtins.readFile ./claude-show/herdr_show.py
            )
          );
    in
    {
      home.packages = [ show ];
      home.file.".claude/skills/herdr-show/SKILL.md".source = ./claude-show/SKILL.md;
    };
}
