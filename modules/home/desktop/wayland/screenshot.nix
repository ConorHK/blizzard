{
  flake.modules.homeManager.screenshot =
    { lib, pkgs, ... }:
    {
      wayland.windowManager.hyprland.settings.bind =
        let
          screenshot = pkgs.writeShellScriptBin "screenshot" ''
            #!/usr/bin/env bash
            ${lib.getExe pkgs.grimblast} save area - | ${lib.getExe pkgs.satty} --actions-on-escape exit -f -
          '';
        in
        [
          "SUPER, P, exec, ${lib.getExe screenshot}"
        ];
    };
}
