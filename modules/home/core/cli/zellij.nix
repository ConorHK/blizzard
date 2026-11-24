{ config, ... }:
let
  inherit (config.flake.wrappers.zellij) install;
in
{
  flake.modules.homeManager.zellij =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      sesh = pkgs.writeScriptBin "sesh" ''
        #! /usr/bin/env sh

        select_session() {
          ZJ_SESSIONS=$(zellij list-sessions -s)
          NO_SESSIONS=$(echo "$ZJ_SESSIONS" | wc -l)

          if [ -z "$ZELLIJ" ]; then
            if [ "$NO_SESSIONS" -ge 2 ]; then
              zellij attach \
              "$(echo "$ZJ_SESSIONS" | ${lib.getExe config.wrappers.fzf.wrapper})"
            else
               zellij attach -c
            fi
          fi
        }
        select_session
        [ $? -ne 0 ] && zellij attach -c "default"
      '';
    in
    {
      imports = [ install ];
      wrappers.zellij = {
        enable = true;
        shell = lib.getExe config.wrappers.fish.wrapper;
      };

      home.packages = [ sesh ];
    };
}
