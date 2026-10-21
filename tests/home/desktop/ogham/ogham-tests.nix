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
            programs.obsidian.package = null;
          }
        ];
      };
      inherit (home.config.home) activation;
      files = home.config.home-files;
    in
    {
      checks.ogham =
        pkgs.runCommand "ogham-test"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.jq
            ];
          }
          ''
            obsidian=${files}/ogham/.obsidian

            # Plugin dirs must match manifest ids.
            for id in $(jq -r '.[]' "$obsidian/community-plugins.json"); do
              jq -e --arg id "$id" '.id == $id' "$obsidian/plugins/$id/manifest.json" >/dev/null
              test -f "$obsidian/plugins/$id/main.js"
            done
            jq -e 'length == 4' "$obsidian/community-plugins.json" >/dev/null
            jq -e '.["daily-notes"]' "$obsidian/core-plugins.json" >/dev/null

            export HOME=$PWD
            run() { "$@"; }
            ${activation.ogham.data}

            vault=$HOME/ogham
            test -f "$vault/Templates/Daily.md"
            jq -r '.template' "$obsidian/daily-notes.json" | xargs -I{} test -f "$vault/{}.md"
            jq -r '.folder_templates[].template' "$obsidian/plugins/templater-obsidian/data.json" \
              | while read -r template; do test -f "$vault/$template"; done
            git -C "$vault" check-ignore -q .obsidian/app.json

            # Second run keeps user notes.
            echo mine >"$vault/Home.md"
            ${activation.ogham.data}
            grep -qx mine "$vault/Home.md"

            touch "$out"
          '';
    };
}
