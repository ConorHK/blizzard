{
  flake.modules.homeManager.core =
    { lib, pkgs, ... }:
    {
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

            alias =
              let
                switch-branch = pkgs.writeScriptBin "switch-branch" ''
                  #!${pkgs.bash}/bin/bash
                  set -o errexit
                  set -o nounset

                  selected_branch_ref=$(git branch --all --format='%(refname)' --sort='committerdate' | fzf --reverse)
                  selected_branch_ref_prefix=''${selected_branch_ref#*/}
                  selected_branch_source=''${selected_branch_ref_prefix%%/*}

                  if test "$selected_branch_source" = 'remotes'; then
                    branch_with_remote=''${selected_branch_ref#refs/remotes/}
                    branch_without_remote=''${branch_with_remote#*/}
                    (
                      set -x
                      git switch "$branch_without_remote" || git switch -t "$branch_with_remote"
                    )
                  else
                    branch_name=''${selected_branch_ref#refs/heads/}
                    (
                      set -x
                      git switch "$branch_name"
                    )
                  fi
                '';
              in
              {
                # https://bernsteinbear.com/git
                recent = "! git branch --sort=-committerdate --format=\"%(committerdate:relative)%09%(refname:short)\" | head -10";
                switch-branch = "! ${lib.getExe switch-branch}";
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
