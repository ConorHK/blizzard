{
  inputs,
  config,
  lib,
  ...
}:
{
  # Guarding on `system` rather than `pkgs`: deciding the module's shape from
  # `pkgs` is infinite recursion, since `pkgs` is itself a perSystem option.
  perSystem =
    { system, ... }:
    lib.optionalAttrs (lib.hasSuffix "-linux" system) {
      packages.iso =
        let
          sshKeys = config.flake.lib.conorhkSshKeys;

          isoModule =
            { lib, pkgs, ... }:
            {
              environment.systemPackages = lib.attrValues {
                inherit (pkgs)
                  git
                  ripgrep
                  wget
                  file
                  pciutils
                  usbutils
                  ;
                cnvim = inputs.self.packages.${system}.cnvim;
              };

              services.openssh = {
                enable = lib.mkForce true;
                settings.PasswordAuthentication = lib.mkForce false;
              };

              users.users.root.openssh.authorizedKeys.keys = sshKeys;
              users.users.nixos.openssh.authorizedKeys.keys = sshKeys;
            };

          nixos = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
              isoModule
            ];
          };
        in
        nixos.config.system.build.isoImage;
    };
}
