{
  inputs,
  lib,
  config,
  ...
}:
let
  inherit (lib) types mkOption;
in
{
  options = {
    nixosHosts =
      let
        nixosHostType = types.submodule {
          options = {
            system = mkOption {
              type = types.str;
              default = "x86_64-linux";
            };
          };
        };
      in
      mkOption {
        type = types.attrsOf nixosHostType;
        default = { };
      };
  };

  config = {
    flake.nixosConfigurations =
      let
        mkHost =
          hostname: options:
          inputs.nixpkgs.lib.nixosSystem {
            inherit (options) system;
            specialArgs = {
              inherit inputs;
              blizzardLib = config.flake.lib;
              monitoringChecks = lib.attrValues config.flake.monitoringChecks;
            };
            modules = [
              config.flake.modules.nixos.core
              (config.flake.modules.nixos."nixosConfigurations/${hostname}" or { })
            ];
          };
      in
      lib.mapAttrs mkHost config.nixosHosts;
  };
}
