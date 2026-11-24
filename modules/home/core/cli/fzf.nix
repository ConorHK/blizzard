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

      # The widgets load early, so a history manager loaded later can take Ctrl-R.
      programs.zsh.initContent = lib.mkOrder 910 ''
        if [[ $options[zle] = on ]]; then
          source ${share}/key-bindings.zsh
          source ${share}/completion.zsh
        fi
      '';
    };
}
