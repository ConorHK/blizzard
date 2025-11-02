{
  flake.modules.homeManager.nh =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      nh-wrapped = pkgs.writeShellScriptBin "nh" ''
        #!/bin/sh
        cd ${config.programs.nh.flake}
        today=$(date +%Y%m%d)
        branch=$(${lib.getExe pkgs.git} branch 2>/dev/null | sed -n '/^\* / { s|^\* ||; p; }')
        revision=$(${lib.getExe pkgs.git} rev-parse HEAD)
        export NIXOS_LABEL_VERSION="$today.$branch-''${revision:0:7}"
        exec ${pkgs.nh}/bin/nh "$@"
      '';
    in
    {
      programs.nh = {
        enable = true;
        flake = lib.mkDefault "${config.home.homeDirectory}/repositories/blizzard";
        package = nh-wrapped;
      };
    };
}
