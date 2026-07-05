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
            set -euo pipefail
            if [ "$#" -ne 1 ]; then
              echo "usage: rebuild <hostname>" >&2
              exit 1
            fi
            hostname=$1

            echo -e "\n=> Deploying system '$hostname'"
            nh os switch \
                --hostname "$hostname" \
                --target-host "root@$hostname" \
                --build-host "root@$hostname"
          '';
          rebuild-home.exec = ''
            set -euo pipefail
            if [ "$#" -ne 1 ]; then
              echo "usage: rebuild-home <user@host>" >&2
              exit 1
            fi
            home=$1

            echo -e "\n=> Deploying home configuration '$home'"
            home-manager switch --flake ".#$home" \
                --extra-experimental-features pipe-operators
          '';
          make-iso.exec = ''
            echo -e "\n=> Building bootable ISO..."
            nix build .#iso --out-link result-iso
            echo -e "\n=> ISO ready:"
            ls -lh result-iso/iso/*.iso
          '';
          # Fast smoke test: force every host's toplevel to *evaluate* (catching a
          # host that no longer evaluates) without building anything. Building each
          # host is CI's job (.github/workflows/build.yml); this stays cheap/local.
          check-hosts.exec = ''
            echo -e "\n=> Evaluating every host toplevel (eval-only, no build)..."
            nix eval --no-pure-eval --raw .#nixosConfigurations --apply \
              'cfgs: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: cfg: "  " + name + "  ->  " + cfg.config.system.build.toplevel.drvPath) cfgs))'
            echo
          '';
        };
      };
    };
}
