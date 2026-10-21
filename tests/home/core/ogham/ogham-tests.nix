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
            echo note >solo/a.md
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1
            ${ogham} sync solo
            test "$(git -C solo rev-list --count HEAD)" = 1

            # Two clones sync through the hub.
            git init -q --bare -b mainline hub.git
            git clone -q hub.git seed
            echo hub >seed/hub.md
            git -C seed add hub.md
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
