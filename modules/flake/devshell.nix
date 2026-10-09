{
  perSystem =
    {
      config,
      inputs',
      pkgs,
      ...
    }:
    let
      script = name: text: pkgs.writeShellApplication { inherit name text; };
    in
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.pre-commit.devShell ];

        packages = [
          inputs'.agenix-rekey.packages.default
          inputs'.home-manager.packages.default
          pkgs.age-plugin-yubikey
          config.packages.dns-sync

          (script "rebuild" ''
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
          '')

          (script "rebuild-home" ''
            if [ "$#" -ne 1 ]; then
              echo "usage: rebuild-home <user@host>" >&2
              exit 1
            fi
            home=$1

            echo -e "\n=> Deploying home configuration '$home'"
            home-manager switch --flake ".#$home" \
              --extra-experimental-features pipe-operators
          '')

          (script "make-iso" ''
            echo -e "\n=> Building bootable ISO..."
            nix build .#iso --out-link result-iso
            echo -e "\n=> ISO ready:"
            ls -lh result-iso/iso/*.iso
          '')

          # Eval-only smoke test; CI does the builds.
          (script "check-hosts" ''
            echo -e "\n=> Evaluating every host toplevel (eval-only, no build)..."
            nix eval --raw .#nixosConfigurations --apply \
              'cfgs: builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs (name: cfg: "  " + name + "  ->  " + cfg.config.system.build.toplevel.drvPath) cfgs))'
            echo
          '')
        ];

        # Rekeyed secrets land in git without `agenix rekey -a`.
        AGENIX_REKEY_ADD_TO_GIT = "true";
      };
    };
}
