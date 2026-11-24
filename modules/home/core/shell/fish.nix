{ config, ... }:
let
  inherit (config.flake.wrappers.fish) install;
in
{
  flake.modules.homeManager.core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # fish cannot read hm-session-vars.sh.
      sessionVariables = pkgs.runCommandLocal "hm-session-vars.fish" { } ''
        {
          echo "function setup_hm_session_vars;"
          ${pkgs.buildPackages.babelfish}/bin/babelfish \
            < ${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh
          echo "end"
          echo "setup_hm_session_vars"
        } > $out
      '';
    in
    {
      imports = [ install ];
      wrappers.fish.enable = true;

      home.sessionVariables.SHELLS = lib.getExe config.wrappers.fish.wrapper;

      # fish reads conf.d before the wrapper's config, in scripts too.
      xdg.configFile."fish/conf.d/hm-session-vars.fish".source = sessionVariables;
    };
}
