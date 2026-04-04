{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      packages.iso =
        let
          isoModule =
            { lib, pkgs, ... }:
            let
              keysFile = builtins.readFile (
                builtins.fetchurl {
                  url = "https://github.com/conorhk.keys";
                  sha256 = "0dsy8sv3xzvai7lh3im1vr91gymm7p0ngrdys720wcnzgla2a9wi";
                }
              );
              sshKeys = builtins.filter (x: x != "") (lib.splitString "\n" keysFile);
            in
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
