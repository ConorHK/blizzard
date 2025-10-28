{
  flake.modules.homeManager.core =
    { lib, pkgs, ... }:
    {
      home.packages = [ pkgs.pre-commit ];
      programs = {
        difftastic = {
          enable = true;
          git.enable = true;
          options.background = "dark";
        };

        git = {
          enable = true;
          lfs.enable = true;

          settings = lib.mkDefault {
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

            alias = {
              # https://bernsteinbear.com/git
              recent = "! git branch --sort=-committerdate --format=\"%(committerdate:relative)%09%(refname:short)\" | head -10";
              switch-branch = "! git branch --sort=committerdate | ${lib.getExe pkgs.fzf} --reverse | xargs -I {} git checkout {}";
            };
          };
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
