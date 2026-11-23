{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.git = pkgs.runCommand "git-test" { } ''
        export HOME=$TMPDIR
        git=${lib.getExe self'.packages.git}
        $git init --quiet repo
        cd repo
        test "$($git config rebase.updateRefs)" = true
        mkdir .zvec-grep
        touch .zvec-grep/index
        test -z "$($git status --porcelain)"
        $git lfs version > /dev/null

        # The build's PATH has no fzf, so the alias runs the one the wrapper brings.
        grep --quiet FZF_DEFAULT_OPTS_FILE "$($git -c alias.which-fzf='! command -v fzf' which-fzf)"
        $git -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty --message init
        $git branch feature
        FZF_DEFAULT_OPTS=--filter=feature $git switch-branch
        test "$($git symbolic-ref --short HEAD)" = feature
        touch "$out"
      '';
    };
}
