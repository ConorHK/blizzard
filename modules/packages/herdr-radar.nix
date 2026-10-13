{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-radar = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "herdr-radar";
        version = "1.4.4";

        src = pkgs.fetchFromGitHub {
          owner = "hhdebb";
          repo = "herdr-radar";
          tag = "v${finalAttrs.version}";
          hash = "sha256-aFQqPFSNG33Ois2niAwKrQXqNWgNqreO282PdXSzSEw=";
        };

        patches = [ ./herdr-radar/text-skips-font.patch ];

        dontConfigure = true;
        dontBuild = true;

        doCheck = true;
        nativeCheckInputs = [
          pkgs.git
          pkgs.nodejs
        ];
        checkPhase = ''
          runHook preCheck
          node --test
          runHook postCheck
        '';

        # Herdr may lack node on PATH.
        installPhase = ''
          runHook preInstall
          root=$out/share/herdr-radar
          mkdir -p $root
          cp -r herdr-plugin.toml package.json bin lib dist $root/
          substituteInPlace $root/herdr-plugin.toml \
            --replace-fail '["node", ' '["${lib.getExe pkgs.nodejs}", '
          runHook postInstall
        '';

        # Bakes blocks the plugin cannot write.
        passthru.configure =
          {
            base,
            settings,
            stateDir,
            appearance ? "dark",
          }:
          pkgs.runCommand "herdr.toml"
            {
              nativeBuildInputs = [
                pkgs.herdr
                pkgs.nodejs
              ];
              HERDR_RADAR_STATE = stateDir;
            }
            ''
              root=${finalAttrs.finalPackage}/share/herdr-radar
              export HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR/config XDG_STATE_HOME=$TMPDIR/state
              export HERDR_PLUGIN_CONFIG_DIR=$TMPDIR/settings
              known=$XDG_STATE_HOME/herdr/agent-detection/remote
              mkdir -p $XDG_CONFIG_HOME/herdr $known $HERDR_PLUGIN_CONFIG_DIR
              cp ${settings} $HERDR_PLUGIN_CONFIG_DIR/config.toml

              # Unknown rows_by_agent ids break the config.
              for agent in $(node -p "Object.keys(require('$root/lib/palette').brand).join(' ')"); do
                printf '[ui.sidebar.agents.rows_by_agent]\n%s = [["$gap"]]\n' "$agent" \
                  > $XDG_CONFIG_HOME/herdr/config.toml
                if herdr config check >/dev/null; then touch $known/$agent.toml; fi
              done

              node ${./herdr-radar/splice-blocks.js} $root ${base} ${appearance} > $out
              cp $out $XDG_CONFIG_HOME/herdr/config.toml
              herdr config check
            '';

        meta = {
          description = "Herdr plugin that shows agent state in the sidebar";
          homepage = "https://github.com/hhdebb/herdr-radar";
          license = lib.licenses.mit;
        };
      });
    };
}
