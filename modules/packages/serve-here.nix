{
  perSystem =
    { pkgs, ... }:
    {
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
        pkgs.writeShellApplication {
          name = "serve-here";
          runtimeInputs = [
            pkgs.iptables
            (pkgs.python3.withPackages (_: [ uploadserver ]))
          ];
          text = builtins.readFile ./serve-here.sh;
        };
    };
}
