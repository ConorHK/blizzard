{ config, ... }:
let
  inherit (config.flake.wrappers.fzf) install;
in
{
  flake.modules.homeManager.core =
    { config, lib, ... }:
    let
      share = "${config.wrappers.fzf.wrapper}/share/fzf";
    in
    {
      imports = [ install ];
      wrappers.fzf.enable = true;

      # The shell widgets read these, not fzf.
      home.sessionVariables = {
        FZF_CTRL_T_OPTS = "--preview 'head {}'";
        FZF_CTRL_R_OPTS = "--sort";
      };

      # The widgets load early, so a history manager loaded later can take Ctrl-R.
      programs = {
        fish.interactiveShellInit = lib.mkOrder 200 ''
          source ${share}/key-bindings.fish
          source ${share}/completion.fish
        '';
        bash.initExtra = lib.mkOrder 200 ''
          if [[ :$SHELLOPTS: =~ :(vi|emacs): ]]; then
            source ${share}/key-bindings.bash
            source ${share}/completion.bash
          fi
        '';
        zsh.initContent = lib.mkOrder 910 ''
          if [[ $options[zle] = on ]]; then
            source ${share}/key-bindings.zsh
            source ${share}/completion.zsh
          fi
        '';
      };
    };
}
