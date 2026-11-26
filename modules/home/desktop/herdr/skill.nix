{ inputs, ... }:
{
  # The tools' own manuals as skills for claude-code and pi, so they match the installed versions.
  flake.modules.homeManager.herdr =
    { lib, pkgs, ... }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-app herdr-core;
      skills = {
        hc = {
          bin = lib.getExe' herdr-core "hc";
          description = "Start, message, wait on and read agents and programs in herdr-core terminals with hc. Use to delegate work to other agents, run slow commands without blocking, or reach other machines.";
        };
        herdr-app = {
          bin = lib.getExe herdr-app;
          description = "Change what the person sees in the Herdr window with herdr-app, such as spaces, tabs, panes, layouts and focus. Use hc, not this, to run or message agents.";
        };
      };
      skillFile =
        name: s:
        pkgs.runCommand "${name}-skill.md" { } ''
          {
            printf '%s\n' '---' ${lib.escapeShellArg "name: ${name}"} \
              ${lib.escapeShellArg "description: ${s.description}"} '---' ""
            HOME=$TMPDIR ${s.bin} --skill
          } > $out
        '';
    in
    {
      home.file = lib.concatMapAttrs (
        name: s:
        let
          file = skillFile name s;
        in
        {
          ".claude/skills/${name}/SKILL.md".source = file;
          ".pi/agent/skills/${name}/SKILL.md".source = file;
        }
      ) skills;
    };
}
