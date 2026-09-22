{
  perSystem =
    { pkgs, ... }:
    {
      checks.security-scripts =
        pkgs.runCommand "security-scripts"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.bash
              pkgs.coreutils
              pkgs.bubblewrap
            ];
            src = ../..;
          }
          ''
            export PYTHONDONTWRITEBYTECODE=1
            python "$src/tests/security.py"
            touch "$out"
          '';
    };
}
