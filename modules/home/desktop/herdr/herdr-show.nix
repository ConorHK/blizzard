{ inputs, ... }:
{
  # herdr-show draws a page in the canvas sidebar: pi's show_ui tool runs it, and Claude Code learns it from a skill.
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
              builtins.readFile ./herdr-show/herdr_show.py
            )
          );
    in
    {
      home.packages = [ show ];
      home.file.".claude/skills/herdr-show/SKILL.md".source = ./herdr-show/SKILL.md;
    };
}
