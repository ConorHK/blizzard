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

            # No remote: local repo, commit only.
            ${ogham} init solo
            echo note >solo/a.md
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1

            # A plain directory is left alone.
            mkdir plain
            ${ogham} init plain "$PWD/hub.git"
            test ! -e plain/.git

            # Two clones sync through the hub.
            git init -q --bare -b mainline hub.git
            git clone -q hub.git seed
            git -C seed commit -q --allow-empty -m init
            git -C seed push -q origin HEAD:mainline
            ${ogham} init laptop "$PWD/hub.git"
            ${ogham} init desk "$PWD/hub.git"
            echo desk >desk/a.md
            ${ogham} sync desk
            echo laptop >laptop/b.md
            ${ogham} sync laptop
            ${ogham} sync desk
            test "$(cat desk/b.md)" = laptop
            test "$(cat laptop/a.md)" = desk

            touch "$out"
          '';
    };
}
