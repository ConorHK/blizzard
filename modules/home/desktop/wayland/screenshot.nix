{
  flake.modules.wrapper."hyprland/screenshot" =
    { config, lib, ... }:
    {
      settings.bind =
        let
          inherit (config) pkgs;
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
