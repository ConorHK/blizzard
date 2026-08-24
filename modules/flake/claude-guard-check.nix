{
  # `nix flake check` gate for the Claude auto-mode guard. Builds the guard with
  # the SAME writeShellApplication used by the home module (so its build-time
  # shellcheck pass runs here too) and then runs the committed regression suite
  # against that binary. A future edit that reintroduces a slip-through (a
  # mutating push that defers) or a false positive (a read-only action that
  # gets denied) fails the build instead of shipping silently.
  perSystem =
    { pkgs, ... }:
    let
      guardDir = ../home/core/cli/claude;
      guard = pkgs.writeShellApplication {
        name = "claude-auto-mode-guard";
        runtimeInputs = [
          pkgs.jq
          pkgs.git
        ];
        text = builtins.readFile "${guardDir}/auto-mode-guard.sh";
      };
    in
    {
      checks.claude-auto-mode-guard =
        pkgs.runCommand "claude-auto-mode-guard-test"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.jq
              pkgs.git
            ];
          }
          ''
            # A clean HOME so git uses no user config, and a deterministic identity.
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            bash ${guardDir}/auto-mode-guard-test.sh ${guard}/bin/claude-auto-mode-guard
            touch "$out"
          '';
    };
}
