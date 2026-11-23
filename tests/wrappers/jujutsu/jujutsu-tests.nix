{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.jujutsu = pkgs.runCommand "jujutsu-test" { } ''
        export HOME=$TMPDIR
        jj=${lib.getExe self'.packages.jujutsu}
        test "$($jj config get user.email)" = dev@conorknowles.com
        $jj git init --quiet repo
        cd repo
        echo hello > note.txt
        # Only difftastic, the configured formatter, prints this marker.
        $jj diff > diff
        grep --quiet -- '--- Text' diff
        touch "$out"
      '';
    };
}
