{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      # Zathura reads its config once it has a display; GTK's broadway server is one with no screen.
      checks.zathura = pkgs.runCommand "zathura-test" { } ''
        export HOME=$TMPDIR XDG_RUNTIME_DIR=$TMPDIR/runtime
        export GDK_BACKEND=broadway BROADWAY_DISPLAY=:7
        mkdir --mode=700 "$XDG_RUNTIME_DIR"

        ${pkgs.gtk4}/bin/gtk4-broadwayd :7 > /dev/null 2>&1 &
        display=$!
        for _ in $(seq 100); do
          test -S "$XDG_RUNTIME_DIR/broadway8.socket" && break
          sleep 0.1
        done

        ${lib.getExe self'.packages.zathura} --log-level=debug > log 2>&1 &
        viewer=$!
        loaded="reading configuration file '$NIX_STORE/[^']*-zathura-config/zathurarc'"
        for _ in $(seq 120); do
          grep --quiet "$loaded" log && break
          sleep 0.5
        done
        sleep 1
        kill $viewer $display || true

        grep --quiet "$loaded" log
        if grep -e "failed to open config file '$NIX_STORE" -e 'Unknown option' -e 'Could not process line' log; then
          exit 1
        fi
        touch "$out"
      '';
    };
}
