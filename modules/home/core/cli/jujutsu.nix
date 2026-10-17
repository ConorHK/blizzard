{
  flake.modules.homeManager.jujutsu = {
    programs = {
      jujutsu = {
        enable = true;
        # jj sync [revset]: fetch, then rebase @'s branch onto it.
        settings.aliases.sync = [
          "util"
          "exec"
          "--"
          "bash"
          "-c"
          "jj git fetch && jj rebase -o \"\${1:-trunk()}\""
          ""
        ];
      };
      difftastic.jujutsu.enable = true;
    };
  };
}
