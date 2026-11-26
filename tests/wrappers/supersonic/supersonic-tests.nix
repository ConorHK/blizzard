{
  perSystem =
    { pkgs, self', ... }:
    {
      checks.supersonic = pkgs.runCommand "supersonic-test" { } ''
        export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config
        conf=$XDG_CONFIG_HOME/supersonic/config.toml
        mkdir --parents $(dirname $conf)
        cat > $conf <<'EOF'
        [Application]
        WindowWidth = 1234
        EnableAutoUpdateChecker = true

        [[Servers]]
        Hostname = "https://music.example"
        EOF

        ${self'.packages.supersonic}/bin/supersonic -version

        grep --quiet 'WindowWidth = 1234' $conf
        grep --quiet 'Hostname = "https://music.example"' $conf
        grep --quiet 'EnableAutoUpdateChecker = false' $conf
        font=$(grep --only-matching '/nix/store/[^"]*creeper-regular.ttf' $conf)
        test -f "$font"
        grep --quiet 'Name = "Blizzard"' $XDG_CONFIG_HOME/supersonic/themes/blizzard.toml
        touch "$out"
      '';
    };
}
