{ config, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          config.flake.modules.homeManager.ogham
          {
            home = {
              username = "test";
              homeDirectory = "/home/test";
              stateVersion = "25.05";
            };
            programs.ogham.enable = true;
          }
        ];
      };
      ogham = pkgs.lib.getExe home.config.programs.ogham.package;
    in
    {
      checks.ogham =
        pkgs.runCommand "ogham-test"
          {
            nativeBuildInputs = [ pkgs.git ];
            GIT_AUTHOR_NAME = "test";
            GIT_AUTHOR_EMAIL = "test@example.com";
            GIT_COMMITTER_NAME = "test";
            GIT_COMMITTER_EMAIL = "test@example.com";
          }
          ''
            grep -q 'ogham init /home/test/ogham' <<<${pkgs.lib.escapeShellArg home.config.home.activation.ogham.data}
            grep -q 'export PATH="[^"]*${pkgs.openssh}/bin' ${ogham}

            # No remote: local repo, commit only.
            ${ogham} init solo
            mkdir solo/.zvec-grep
            touch solo/.zvec-grep/index solo/a.md.123.tmp
            : >solo/.git/info/exclude
            echo note >solo/a.md
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1
            test "$(git -C solo ls-files)" = a.md
            ${ogham} init solo
            ${ogham} sync solo
            test "$(grep -c zvec-grep solo/.git/info/exclude)" = 1
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1

            # Two clones sync through the hub.
            git init -q --bare -b mainline hub.git
            git clone -q hub.git seed
            echo hub >seed/hub.md
            echo old >seed/index.md
            git -C seed add hub.md index.md
            git -C seed commit -q -m init
            git -C seed push -q origin HEAD:mainline

            # A plain directory is adopted, files kept.
            mkdir -p plain/projects
            echo mine >plain/projects/a.md
            ${ogham} init plain "$PWD/hub.git"
            test "$(cat plain/projects/a.md)" = mine
            test "$(cat plain/hub.md)" = hub
            ${ogham} sync plain
            git -C hub.git cat-file -e mainline:projects/a.md

            # index.md is per host: it leaves the hub, the file stays.
            if git -C hub.git cat-file -e mainline:index.md; then exit 1; fi
            test "$(cat plain/index.md)" = old

            ${ogham} init laptop "$PWD/hub.git"
            ${ogham} init desk "$PWD/hub.git"
            echo desk >desk/a.md
            ${ogham} sync desk
            echo laptop >laptop/b.md
            ${ogham} sync laptop
            ${ogham} sync desk
            test "$(cat desk/b.md)" = laptop
            test "$(cat laptop/a.md)" = desk

            # Both hosts append a win; union merge keeps both.
            echo '# Wins' >desk/wins.md
            ${ogham} sync desk
            ${ogham} sync laptop
            echo desk-win >>desk/wins.md
            echo laptop-win >>laptop/wins.md
            ${ogham} sync desk
            ${ogham} sync laptop
            grep -qx desk-win laptop/wins.md
            grep -qx laptop-win laptop/wins.md
            ${ogham} sync desk
            test "$(wc -l <desk/wins.md)" = 3

            # A real conflict stops sync and leaves a marker.
            echo desk2 >desk/a.md
            ${ogham} sync desk
            echo laptop2 >laptop/a.md
            if ${ogham} sync laptop; then exit 1; fi
            grep -q 'resolve .*laptop by hand' laptop/.git/ogham-sync-error
            test "$(cat laptop/a.md)" = laptop2
            test ! -d laptop/.git/rebase-merge

            # Resolving by hand clears it.
            git -C laptop reset -q --hard FETCH_HEAD
            ${ogham} sync laptop
            test ! -e laptop/.git/ogham-sync-error
            test "$(cat laptop/a.md)" = desk2

            touch "$out"
          '';
    };
}
