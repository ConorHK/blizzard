{ config, ... }:
let
  inherit (config.flake.wrappers.starship) install;
in
{
  flake.modules.homeManager.core =
    { config, lib, ... }:
    {
      imports = [ install ];
      wrappers.starship.enable = true;

      programs.zsh.initContent = ''
        if [[ $TERM != "dumb" ]]; then
          eval "$(${lib.getExe config.wrappers.starship.wrapper} init zsh)"
        fi
      '';
    };
}
