let
  # Last non-empty commit: @, or @- after `jj commit`.
  tip = "heads(::@ ~ (@ & empty()))";
in
{
  flake.modules.homeManager.jujutsu = {
    programs = {
      jujutsu = {
        enable = true;
        settings.aliases = {
          # jj sync [revset]: fetch, then rebase @'s branch onto it.
          sync = [
            "util"
            "exec"
            "--"
            "bash"
            "-c"
            "jj git fetch && jj rebase -o \"\${1:-trunk()}\""
            ""
          ];
          # jj push [bookmark]: point a bookmark at the tip, then push.
          # No name moves the nearest ancestor bookmark forward.
          push = [
            "util"
            "exec"
            "--"
            "bash"
            "-c"
            ''
              if [ -n "''${1:-}" ]; then
                jj bookmark set "$1" -r '${tip}' && jj git push -b "$1"
              else
                jj bookmark move --from 'heads(::${tip} & bookmarks())' --to '${tip}' && jj git push
              fi
            ''
            ""
          ];
        };
      };
      difftastic.jujutsu.enable = true;
    };
  };
}
