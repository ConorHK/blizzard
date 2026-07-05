{
  lib,
  ...
}:
let
  inherit (lib) types mkOption;

  # Define the module that can be imported by downstream flakes
  standaloneHomesModule =
    {
      inputs,
      lib,
      config,
      ...
    }:
    {
      options = {
        homeConfigurations =
          let
            homeConfigurationType = types.submodule {
              options = {
                username = mkOption {
                  type = types.str;
                  default = "goose";
                };

                homeDirectory = mkOption {
                  type = types.str;
                  default = "/home/goose";
                };

                system = mkOption {
                  type = types.str;
                  default = "x86_64-linux";
                };

                unstable = lib.mkOption {
                  type = types.bool;
                  default = true;
                };

                stateVersion = lib.mkOption {
                  type = types.str;
                  default = "25.05";
                };

                allowUnfree = lib.mkOption {
                  type = types.bool;
                  default = true;
                };
              };
            };
          in
          mkOption {
            type = types.attrsOf homeConfigurationType;
            default = { };
          };
      };

      config = {
        flake.homeConfigurations =
          let
            mkHome =
              name: options:
              let
                # Blizzard itself only tracks unstable; the stable branch is for
                # downstream flakes, which must provide their own `nixpkgs-stable`.
                nixpkgs' =
                  if options.unstable then
                    inputs.nixpkgs
                  else
                    inputs.nixpkgs-stable
                      or (throw "homeConfigurations.${name} sets unstable = false, but this flake has no `nixpkgs-stable` input");
              in
              inputs.home-manager.lib.homeManagerConfiguration {
                pkgs = import nixpkgs' {
                  inherit (options) system;
                  config.allowUnfree = options.allowUnfree;
                };
                extraSpecialArgs.inputs = inputs;
                modules = [
                  {
                    home = {
                      inherit (options) username homeDirectory stateVersion;
                    };
                    nix.package = lib.mkDefault nixpkgs'.legacyPackages.${options.system}.nix;
                  }
                  config.flake.modules.homeManager.core
                  (config.flake.modules.homeManager.theme or { })
                  (config.flake.modules.homeManager."homeConfigurations/${name}" or { })
                ];
              };
          in
          lib.mapAttrs mkHome config.homeConfigurations;
      };
    };
in
{
  # Use the module locally
  imports = [ standaloneHomesModule ];

  # Export the module for downstream flakes
  config.flake.flakeModules.homeConfigurations = standaloneHomesModule;
}
