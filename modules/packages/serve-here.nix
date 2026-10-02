{ lib, ... }:
{
  # Punches a hole in the NixOS firewall with iptables. Guarding on `system`
  # rather than `pkgs`, which would recurse — see iso.nix.
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (lib.hasSuffix "-linux" system) {
      packages.serve-here =
        let
          uploadserver = pkgs.python3Packages.buildPythonPackage rec {
            pname = "uploadserver";
            version = "5.2.1";

            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-qp2xkzLvnrnx8dHZpwlF3RjRg8jYC7WAaVS4ltJFZaU=";
            };

            doCheck = false;
            pyproject = true;
            build-system = [ pkgs.python3Packages.setuptools ];
          };
        in
        pkgs.writeShellScriptBin "serve-here" ''
          set -e

          PORT=''${1:-8000}

          ${pkgs.iptables}/bin/iptables -I nixos-fw -p tcp --dport "$PORT" -j ACCEPT

          trap '${pkgs.iptables}/bin/iptables -D nixos-fw -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null || true' EXIT INT TERM

          exec ${pkgs.python3.withPackages (_: [ uploadserver ])}/bin/python -m uploadserver "''${@}"
        '';
    };
}
