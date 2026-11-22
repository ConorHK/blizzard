{
  perSystem =
    { pkgs, ... }:
    {
      # The merge gate is what keeps a bad review from reaching main, so its rules are tested here.
      checks.claude-ci-unit =
        pkgs.runCommand "claude-ci-unit"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (ps: [
                ps.anthropic
                ps.pydantic
              ]))
            ];
          }
          ''
            cp -r ${../../modules/packages/claude-ci} src
            chmod -R +w src
            cd src
            python -m unittest discover -s tests -t . -v 2>&1 | tee "$out"
          '';
    };
}
