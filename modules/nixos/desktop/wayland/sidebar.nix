{ config, ... }:
let
  inherit (config.flake.wrappers.eww) install;
in
{
  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      eww = lib.getExe config.wrappers.eww.wrapper;
      open = pkgs.writeShellApplication {
        name = "sidebar-open";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          for _ in $(seq 50); do
            ${eww} ping >/dev/null 2>&1 && break
            sleep 0.1
          done
          ${
            if config.wrappers.eww.output != null then
              "screens=(${lib.escapeShellArg config.wrappers.eww.output})"
            else
              "mapfile -t screens < <(hyprctl monitors -j | jq -r '.[].name')"
          }
          args=()
          for screen in "''${screens[@]}"; do
            args+=("sidebar:$screen" --arg "$screen:screen=$screen")
          done
          ${eww} open-many "''${args[@]}"
        '';
      };
    in
    {
      imports = [ install ];
      wrappers.eww.enable = true;

      systemd.user.services.sidebar = {
        description = "eww sidebar";
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
        # The sidebar's click commands and hyprctl come from the session's PATH.
        enableDefaultPath = false;
        serviceConfig = {
          ExecStart = "${eww} daemon --no-daemonize";
          ExecStartPost = lib.getExe open;
          ExecStop = "${eww} kill";
          Restart = "on-failure";
        };
      };
    };
}
