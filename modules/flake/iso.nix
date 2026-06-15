{ inputs, config, ... }:
{
  perSystem =
    { system, ... }:
    {
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
                cnvim = inputs.cnvim.packages.${system}.default;
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
