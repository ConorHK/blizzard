{ inputs, ... }:
{
  # A tree of spaces in place of the spaces and agents lists and the tab bar, a canvas sidebar for
  # what pi's show_ui tool draws, and terminals that come back after a reboot.
  flake.modules.homeManager.herdr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-core;
      inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
      cfg = config.programs.herdr-app;
      herdr = config.lib.herdr;

      border = {
        width = 1;
        color = "border";
      };
      # One tree of spaces, their tabs and each tab's agents.
      tree = {
        id = "tree";
        type = "block";
        size.weight = 3;
        min = 90;
        content = {
          mod = "tree";
          props = herdr.text // {
            menu = "${herdr.prefix}menu";
            newMenu = "${herdr.prefix}new-menu";
            # The tree keeps each space on the layout it last showed.
            follow = {
              inherit (herdr) home;
              inherit (cfg) views;
            };
          };
        };
      };
      # The sidebar's lower half: the added blocks, tabbed by title when there are several.
      blocks = map (b: removeAttrs b [ "title" ]) cfg.sidebar.blocks;
      tabs = map (b: {
        inherit (b) id;
        title = b.title or b.id;
      }) cfg.sidebar.blocks;
      lower =
        if blocks == [ ] then
          [ ]
        else if lib.length blocks == 1 then
          [ (lib.head blocks // { size.weight = 3; }) ]
        else
          [
            {
              id = "sidebar-lower";
              type = "column";
              size.weight = 3;
              min = 120;
              children = [
                {
                  id = "sidebar-tabs";
                  type = "block";
                  size.px = 31;
                  content = {
                    mod = "sidebar-tabs";
                    props = herdr.text // {
                      stack = "sidebar-stack";
                      inherit tabs;
                    };
                  };
                }
                {
                  id = "sidebar-stack";
                  type = "stack";
                  active = (lib.head blocks).id;
                  children = blocks;
                }
              ];
            }
          ];
      # The right sidebar of what pi's show_ui tool draws, hidden until its key shows it.
      canvas = {
        id = "canvas";
        type = "column";
        hidden = true;
        size.px = 440;
        min = 280;
        max = 900;
        children = [
          {
            id = "canvas-body";
            type = "block";
            content = {
              mod = "canvas";
              # The mod copies a remote session's images with hc.
              props.hc = lib.getExe herdr-core;
            };
          }
          # A second child, so Herdr never merges this column away with its hidden flag.
          {
            id = "canvas-spacer";
            type = "block";
            size.px = 0;
            content.mod = "spacer";
          }
        ];
      };
      # An invisible floating copy of the canvas mod: it opens the canvas on a new show_ui and
      # keeps it open or closed per space.
      canvasWatch = {
        id = "canvas-watch";
        content = {
          mod = "canvas";
          props.role = "watch";
        };
        edge = "right";
        align = "end";
      };

      resume = pkgs.writers.writePython3 "herdr-resume" { flakeIgnore = [ "E501" ]; } (
        builtins.replaceStrings [ "@hc@" ] [ (lib.getExe herdr-core) ] (builtins.readFile ./resume.py)
      );

      # Herdr resolves imports after symlinks, so each mod is bundled into one linked file.
      bundle =
        mod: dir:
        pkgs.runCommand "herdr-${mod}-mod" { nativeBuildInputs = [ pkgs.esbuild ]; } ''
          mkdir $out
          esbuild ${dir}/main.js --bundle --format=esm --log-level=warning \
            --external:gpui-kit --external:gpui-base --external:herdr --external:fs/promises \
            --outfile=$out/main.js
          cp ${dir}/mod.json $out/mod.json
        '';
      # Linked per file, since the app writes type files into mod folders.
      modFiles = mod: dir: {
        "herdr-app/mods/${mod}/main.js".source = "${bundle mod dir}/main.js";
        "herdr-app/mods/${mod}/mod.json".source = "${bundle mod dir}/mod.json";
      };
      json = v: lib.escapeShellArg (builtins.toJSON v);
      treeIcons = lib.fileset.toSource {
        root = ./tree/icons;
        fileset = lib.fileset.fileFilter (f: f.hasExt "svg") ./tree/icons;
      };
    in
    {
      options.programs.herdr-app = {
        views = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = "Layouts that stay with the space that showed them.";
        };
        sidebar.blocks = lib.mkOption {
          type = with lib.types; listOf attrs;
          default = [ ];
          description = "Layout blocks in the lower half of the home layout's sidebar, tabbed by an optional `title`.";
        };
      };

      config = {
        lib.herdr = {
          inherit
            border
            tree
            canvas
            canvasWatch
            modFiles
            ;
          # Views import it to hand their layout to a space they open.
          spaceLayout = ./tree/space-layout.js;
        };

        xdg.configFile =
          modFiles "tree" ./tree // modFiles "canvas" ./canvas // modFiles "sidebar-tabs" ./sidebar-tabs;

        programs.herdr-app.keys.global."ctrl-shift-g" = "layout.toggle:canvas";
        programs.pi.showUi.enable = true;

        # Herdr draws no SVG reached through a store symlink, so the icons are copied.
        home.activation.herdrTreeIcons = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          if [[ ! -v DRY_RUN ]]; then
            dir=${config.xdg.configHome}/herdr-app/mods/tree/icons
            rm -rf "$dir"
            mkdir -p "$dir"
            install -m644 ${treeIcons}/*.svg "$dir/"
          fi
        '';

        # herdrCreeper rebuilds the home layout at each switch, so the tree and canvas go in after it.
        home.activation.herdrSidebar = lib.hm.dag.entryAfter [ "herdrCreeper" ] ''
          layout=${config.xdg.configHome}/herdr-app/layouts/${herdr.home}.json
          if [[ -f "$layout" && ! -v DRY_RUN ]]; then
            ${lib.getExe pkgs.jq} \
              --argjson lists ${json ([ tree ] ++ lower)} \
              --argjson line ${json border} \
              --argjson col ${json canvas} \
              --argjson watch ${json canvasWatch} \
              'walk(if type != "object" then .
                elif .id == "sidebar-lists" then .children = $lists | .divider = $line
                elif (.children | type) == "array" then .children |= map(select(.id != "tabs"))
                else . end)
                | (if any(.children[]; .id == "canvas") then . else .children += [$col] end)
                | .floating = ([.floating[]? | select(.id != "canvas-watch")] + [$watch])' \
              "$layout" > "$layout.new"
            mv "$layout.new" "$layout"
          fi
        '';

        # herdr-core gives lost terminals back as blank shells, so this reopens agents and replays shell text.
        launchd.agents.herdr-resume = lib.mkIf isDarwin {
          enable = true;
          config = {
            ProgramArguments = [ "${resume}" ];
            RunAtLoad = true;
            StartInterval = 60;
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-resume.log";
          };
        };
        systemd.user = lib.mkIf isLinux {
          services.herdr-resume = {
            Unit.Description = "Restore herdr terminals after a restart";
            Service = {
              Type = "oneshot";
              ExecStart = "${resume}";
            };
          };
          timers.herdr-resume = {
            Unit.Description = "Restore herdr terminals after a restart";
            Timer = {
              OnStartupSec = "30s";
              OnUnitActiveSec = "60s";
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
