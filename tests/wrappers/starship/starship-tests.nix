{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      starship = self'.packages.starship;
    in
    {
      # Both prompts turn the status module on, which starship leaves off by default.
      checks.starship = pkgs.runCommand "starship-test" { } ''
        export HOME=$TMPDIR STARSHIP_SHELL=bash
        ${lib.getExe starship} prompt --status 3 > prompt
        grep --quiet '✘ 3' prompt
        STARSHIP_CONFIG=${starship.configDir}/starship-jj.toml ${lib.getExe starship} prompt --status 3 > prompt
        grep --quiet '✘ 3' prompt
        touch "$out"
      '';
    };
}
