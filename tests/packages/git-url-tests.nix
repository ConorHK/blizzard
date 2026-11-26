{
  perSystem =
    { pkgs, self', ... }:
    {
      checks.git-url = pkgs.runCommand "git-url-test" { nativeBuildInputs = [ pkgs.git ]; } ''
        export HOME=$TMPDIR
        git init -q -b feat repo
        cd repo
        mkdir src && touch src/a.nix
        git add . && git -c user.name=t -c user.email=t@t commit -qm init

        check() {
          got=$(${self'.packages.git-url}/bin/git-url "$@")
          [ "$got" = "$want" ] || { echo "git-url $*: got $got, want $want"; exit 1; }
        }

        git remote add origin git@github.com:owner/repo.git
        want=https://github.com/owner/repo check
        want=https://github.com/owner/repo/blob/feat/src/a.nix check src/a.nix
        want=https://github.com/owner/repo/blob/feat/src/a.nix#L5 check src/a.nix 5
        want=https://github.com/owner/repo/blob/feat/src/a.nix#L5-L10 check src/a.nix 5-10
        want=https://github.com/owner/repo/blob/feat/src/a.nix#L5#L9 check src/a.nix 5,9

        git remote set-url origin https://gitlab.com/group/repo.git
        want=https://gitlab.com/group/repo/-/blob/feat/src/a.nix#L5-10 check src/a.nix 5-10

        git remote set-url origin https://example.com/x.git
        if ${self'.packages.git-url}/bin/git-url 2>/dev/null; then
          echo "unknown remote should fail"; exit 1
        fi
        touch "$out"
      '';
    };
}
