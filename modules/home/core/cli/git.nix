{
  flake.modules.homeManager.core =
    { lib, ... }:
    {
      programs.git = {
        enable = true;
        lfs.enable = true;

        difftastic = {
          enable = true;
          options.background = "dark";
        };

        extraConfig = lib.mkDefault {
          init.defaultBranch = lib.mkDefault "main";

          commit.verbose = true;

          log.date = "iso";
          column.ui = "auto";

          branch.sort = "-committerdate";
          tag.sort = "version:refname";

          diff.algorithm = "histogram";
          diff.colorMoved = "default";

          pull.rebase = true;
          push.autoSetupRemote = true;

          merge.conflictStyle = "zdiff3";

          rebase.autoSquash = true;
          rebase.autoStash = true;
          rebase.updateRefs = true;
          rerere.enabled = true;

          fetch.fsckObjects = true;
          receive.fsckObjects = true;
          transfer.fsckobjects = true;

          # https://bernsteinbear.com/git
          alias.recent = "! git branch --sort=-committerdate --format=\"%(committerdate:relative)%09%(refname:short)\" | head -10";
        };
      };

      home.shellAliases = {
        gs = "git status";
        gc = "git commit";
        ga = "git add";
        gaa = "git add --all";
        gp = "git push";
        gl = "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        gd = "git -c diff.external=difft diff";
        grc = "git -c diff.external=difft show --ext-diff";

      };
    };
}
