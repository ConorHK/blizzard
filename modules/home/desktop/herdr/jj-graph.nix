{
  # A jj log in the sidebar's lower half, after github.com/rabeeh-ta/herdr-git-graph.
  flake.modules.homeManager.herdr =
    { config, lib, ... }:
    let
      herdr = config.lib.herdr;
      icons = lib.fileset.toSource {
        root = ./jj-graph/icons;
        fileset = lib.fileset.fileFilter (f: f.hasExt "svg") ./jj-graph/icons;
      };
    in
    {
      xdg.configFile = herdr.modFiles "jj-graph" ./jj-graph;

      programs.herdr-app.sidebar.blocks = [
        {
          id = "jj";
          type = "block";
          title = "jj";
          min = 120;
          content = {
            mod = "jj-graph";
            # Creeper glyphs advance 512 of 960 units, which sizes the labels.
            props = herdr.text // {
              advance = 512.0 / 960;
            };
          };
        }
      ];

      # Herdr draws no SVG reached through a store symlink, so the icons are copied.
      home.activation.herdrJjGraphIcons = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        if [[ ! -v DRY_RUN ]]; then
          dir=${config.xdg.configHome}/herdr-app/mods/jj-graph/icons
          rm -rf "$dir"
          mkdir -p "$dir"
          install -m644 ${icons}/*.svg "$dir/"
        fi
      '';
    };
}
