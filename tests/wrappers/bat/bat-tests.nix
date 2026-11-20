{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.bat = pkgs.runCommand "bat-test" { } ''
        echo '# comment' > sample.py
        # 135;135;135 is #878787, the comment colour in the wrapped theme.
        COLORTERM=truecolor ${lib.getExe self'.packages.bat} --color=always --paging=never sample.py |
          grep --quiet --fixed-strings '38;2;135;135;135m#'
        touch "$out"
      '';
    };
}
