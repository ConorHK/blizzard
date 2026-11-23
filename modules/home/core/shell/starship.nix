{ config, ... }:
let
  inherit (config.flake.wrappers.starship) install;
in
{
  flake.modules.homeManager.core =
    { config, lib, ... }:
    let
      starship = config.wrappers.starship.wrapper;
    in
    {
      imports = [ install ];
      wrappers.starship.enable = true;

      programs = {
        # starship asks to be set up last.
        fish.interactiveShellInit = lib.mkAfter ''
          # jj prompt in jj repos, git prompt elsewhere
          function __starship_pick --on-variable PWD
              if jj root >/dev/null 2>&1
                  set -gx STARSHIP_CONFIG ${starship.configDir}/starship-jj.toml
              else
                  set -gx STARSHIP_CONFIG ${starship.configDir}/starship.toml
              end
          end
          __starship_pick

          if test "$TERM" != "dumb"
            ${lib.getExe starship} init fish | source
          end
        '';
        bash.initExtra = lib.mkOrder 1900 ''
          if [[ $TERM != "dumb" ]]; then
            eval "$(${lib.getExe starship} init bash --print-full-init)"
          fi
        '';
        zsh.initContent = ''
          if [[ $TERM != "dumb" ]]; then
            eval "$(${lib.getExe starship} init zsh)"
          fi
        '';
      };
    };
}
