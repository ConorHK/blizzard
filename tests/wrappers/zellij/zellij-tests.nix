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

        # Panes start the fish that carries the shared config, not one from PATH.
        config=$(grep --only-matching "$NIX_STORE/[^\"]*config.kdl" setup)
        shell=$(sed --quiet 's/^default_shell "\(.*\)"$/\1/p' "$config")
        TERM=dumb "$shell" --interactive --command 'functions --query gs'
        touch "$out"
      '';
    };
}
