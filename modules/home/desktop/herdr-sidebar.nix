{ inputs, ... }:
{
  # A tree of spaces in place of the spaces and agents lists and the tab bar, a canvas sidebar for
  # what pi's show_ui tool draws, and agent sessions that reopen after a reboot.
  flake.modules.homeManager.herdr-look =
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
            content.mod = "canvas";
          }
        ];
      };
      # An invisible floating copy of the canvas mod that opens the canvas on a new show_ui.
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
        builtins.replaceStrings [ "@hc@" ] [ (lib.getExe herdr-core) ] (builtins.readFile ./herdr-resume.py)
      );

      # Herdr resolves imports after symlinks, so each mod is bundled into one linked file.
      bundle =
        mod: dir:
        pkgs.runCommand "herdr-${mod}-mod" { nativeBuildInputs = [ pkgs.esbuild ]; } ''
          mkdir $out
          esbuild ${dir}/main.js --bundle --format=esm --log-level=warning \
            --external:gpui-kit --external:gpui-base --external:herdr --outfile=$out/main.js
          cp ${dir}/mod.json $out/mod.json
        '';
      # Linked per file, since the app writes type files into mod folders.
      modFiles = mod: dir: {
        "herdr-app/mods/${mod}/main.js".source = "${bundle mod dir}/main.js";
        "herdr-app/mods/${mod}/mod.json".source = "${bundle mod dir}/mod.json";
      };
      json = v: lib.escapeShellArg (builtins.toJSON v);
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
          description = "Layout blocks under the tree in the home layout's sidebar.";
        };
      };

      config = {
        lib.herdr = {
          inherit
            border
            tree
            canvas
            canvasWatch
            ;
          # Views import it to hand their layout to a space they open.
          spaceLayout = ./herdr-tree/space-layout.js;
        };

        xdg.configFile = modFiles "tree" ./herdr-tree // modFiles "canvas" ./herdr-canvas;

        programs.herdr-app.keys.global."ctrl-shift-g" = "layout.toggle:canvas";
        programs.pi.showUi.enable = true;

        # herdrCreeper rebuilds the home layout at each switch, so the tree and canvas go in after it.
        home.activation.herdrSidebar = lib.hm.dag.entryAfter [ "herdrCreeper" ] ''
          layout=${config.xdg.configHome}/herdr-app/layouts/${herdr.home}.json
          if [[ -f "$layout" && ! -v DRY_RUN ]]; then
            ${lib.getExe pkgs.jq} \
              --argjson lists ${json ([ tree ] ++ cfg.sidebar.blocks)} \
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

        # herdr-core gives lost terminals back as shells, so this reopens their pi and Claude sessions.
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
            Unit.Description = "Reopen agent sessions in herdr terminals";
            Service = {
              Type = "oneshot";
              ExecStart = "${resume}";
            };
          };
          timers.herdr-resume = {
            Unit.Description = "Reopen agent sessions in herdr terminals";
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
