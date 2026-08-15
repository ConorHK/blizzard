{ lib, config, ... }:
let
  inherit (lib) types mkOption;
in
{
  options.hyprland = {
    lua = mkOption {
      type = types.attrsOf types.lines;
      default = { };
    };
    perHost = mkOption {
      type = types.attrsOf types.lines;
      default = { };
    };
  };

  config.perSystem =
    { pkgs, system, ... }:
    {
      checks =
        lib.mapAttrs'
          (
            host: nixos:
            lib.nameValuePair "hyprland-${host}" (
              pkgs.runCommand "hyprland-config-${host}" { } ''
                export XDG_RUNTIME_DIR=$(mktemp -d)
                export HOME=$(mktemp -d)
                ${nixos.config.programs.hyprland.package}/bin/hyprland --verify-config
                touch $out
              ''
            )
          )
          (
            lib.filterAttrs (
              _: nixos:
              (nixos.config.programs.hyprland.enable or false)
              && nixos.config.nixpkgs.hostPlatform.system == system
            ) config.flake.nixosConfigurations
          );
    };
}
