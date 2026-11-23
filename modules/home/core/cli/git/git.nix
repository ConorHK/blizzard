{ config, ... }:
let
  inherit (config.flake.wrappers.git) install;
in
{
  flake.modules.homeManager.core =
    { pkgs, ... }:
    {
      imports = [ install ];
      wrappers.git.enable = true;

      home.packages = [
        pkgs.difftastic
        pkgs.git-absorb
        pkgs.pre-commit
      ];

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
