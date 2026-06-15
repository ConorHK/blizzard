{ inputs, ... }:
{
  imports = [
    inputs.devenv.flakeModule
  ];

  perSystem =
    {
      config,
      inputs',
      ...
    }:
    {
      devenv.shells.default = {
        enterShell = config.pre-commit.installationScript;
        packages = [
          inputs'.home-manager.packages.default
        ];
        scripts = {
          rebuild.exec = ''
            hostname=$1

            echo -e "\n=> Deploying system '$hostname'"
            nh os switch \
                --hostname $hostname \
                --target-host root@$hostname \
                --build-host root@$hostname
          '';
          rebuild-home.exec = ''
            home=$1

            echo -e "\n=> Deploying home configuration '$home'"
            home-manager switch --flake .#$home \
                --extra-experimental-features pipe-operators
          '';
          make-iso.exec = ''
            echo -e "\n=> Building bootable ISO..."
            nix build .#iso --out-link result-iso
            echo -e "\n=> ISO ready:"
            ls -lh result-iso/iso/*.iso
          '';
        };
      };
    };
}
