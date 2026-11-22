{
  perSystem =
    { pkgs, lib, ... }:
    {
      packages.claude-ci = pkgs.python3.pkgs.buildPythonApplication {
        pname = "claude-ci";
        version = "0.1.0";
        pyproject = true;
        src = ./claude-ci;
        build-system = [ pkgs.python3.pkgs.setuptools ];
        dependencies = with pkgs.python3.pkgs; [
          anthropic
          pydantic
        ];
        # The unit tests run as checks.claude-ci-unit.
        doCheck = false;
        makeWrapperArgs = [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath [
            pkgs.gh
            pkgs.git
          ])
        ];
        meta = {
          description = "Claude review, merge and fix for blizzard's bot PRs";
          mainProgram = "claude-ci";
        };
      };
    };
}
