{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    let
      kitty = self'.packages.kitty;
      # The settings kitty itself loads, read without opening a window.
      probe = pkgs.writeText "kitty-probe.py" ''
        import os
        from kitty.config import load_config
        from kitty.constants import config_dir

        opts = load_config(os.path.join(config_dir, "kitty.conf"))
        assert opts.shell == "zmx-open", opts.shell
        assert "no-rc" in opts.shell_integration, opts.shell_integration
        for name in ("open-actions.conf", "zmx_kitten.py", "session-autosave.py"):
            assert os.path.exists(os.path.join(config_dir, name)), name
        print("kitty-config-ok")
      '';
      run = exe: ''
        ${exe} +runpy "exec(open('${probe}').read())" | grep --quiet kitty-config-ok
      '';
    in
    {
      checks.kitty = pkgs.runCommand "kitty-test" { } ''
        export HOME=$TMPDIR
        ${run (lib.getExe kitty)}
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin (
          run "${kitty}/Applications/kitty.app/Contents/MacOS/kitty"
        )}
        touch "$out"
      '';
    };
}
