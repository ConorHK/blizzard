{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.zellij = pkgs.runCommand "zellij-test" { } ''
        export HOME=$TMPDIR
        ${lib.getExe self'.packages.zellij} setup --check > setup
        grep --quiet "LOOKING FOR CONFIG FILE FROM.*$NIX_STORE/.*config.kdl" setup
        grep --quiet 'CONFIG FILE.*Well defined' setup
        touch "$out"
      '';
    };
}
