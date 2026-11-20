{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      alacritty = self'.packages.alacritty;
    in
    {
      # Alacritty needs a display to start, so its migrate command reads the file the wrapper passes.
      checks.alacritty = pkgs.runCommand "alacritty-test" { } ''
        export HOME=$TMPDIR
        ${lib.getExe alacritty} migrate --dry-run \
          --config-file ${alacritty.configuration.flags."--config-file".data} > config
        grep --quiet 'background = "#1c1c1c"' config
        touch "$out"
      '';
    };
}
