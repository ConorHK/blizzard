{ inputs, ... }:
{
  flake.modules.homeManager.herdr-app =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-app herdr-core;
      paneGo = lib.genAttrs [ "left" "down" "up" "right" ] (d: "pane.go:${d}");
      bind = action: keys: lib.genAttrs keys (_: action);
    in
    {
      home.packages = [
        herdr-app
        herdr-core
      ];

      # Login shell is crash, so pick fish for new terminals.
      xdg.configFile."herdr-core/config.toml".source =
        (pkgs.formats.toml { }).generate "herdr-core.toml"
          {
            shell = [ (lib.getExe config.programs.fish.package) ];
          };

      # Linked per file, since the app writes type files into mod folders.
      xdg.configFile."herdr-app/mods/bsp/main.js".source = ./herdr-bsp/main.js;
      xdg.configFile."herdr-app/mods/bsp/mod.json".source = ./herdr-bsp/mod.json;

      # The app has no prefix chords, so herdr prefix binds move to alt.
      xdg.configFile."herdr-app/keys.json".text = builtins.toJSON {
        global = {
          "alt-1" = "space.select:1";
          "alt-2" = "space.select:2";
          "alt-3" = "space.select:3";
          "alt-4" = "space.select:4";
          "alt-5" = "space.select:5";
          "alt-6" = "space.select:6";
          "alt-7" = "space.select:7";
          "alt-8" = "space.select:8";
          "alt-9" = "space.select:9";
          "alt-j" = paneGo.down;
          "alt-k" = paneGo.up;
          "alt-l" = paneGo.right;
          "alt-left" = paneGo.left;
          "alt-right" = paneGo.right;
          "ctrl-h" = paneGo.left;
          "ctrl-j" = paneGo.down;
          "ctrl-k" = paneGo.up;
          "ctrl-l" = paneGo.right;
          "ctrl-left" = paneGo.left;
          "ctrl-down" = paneGo.down;
          "ctrl-up" = paneGo.up;
          "ctrl-right" = paneGo.right;
          "alt-shift-h" = "pane.swap:left";
          "alt-shift-j" = "pane.swap:down";
          "alt-shift-k" = "pane.swap:up";
          "alt-shift-l" = "pane.swap:right";
          "ctrl-+" = "app.zoom_in";
          "ctrl--" = "app.zoom_out";
          "ctrl-0" = "app.zoom_reset";
          "ctrl-=" = "app.zoom_in";
          "ctrl-1" = "tab.select:1";
          "ctrl-2" = "tab.select:2";
          "ctrl-3" = "tab.select:3";
          "ctrl-4" = "tab.select:4";
          "ctrl-5" = "tab.select:5";
          "ctrl-6" = "tab.select:6";
          "ctrl-7" = "tab.select:7";
          "ctrl-8" = "tab.select:8";
          "ctrl-9" = "tab.select:9";
          "ctrl-pagedown" = "tab.next";
          "ctrl-pageup" = "tab.prev";
          "ctrl-tab" = "tab.next";
          "ctrl-shift-tab" = "tab.prev";
          "alt-]" = "tab.next";
          "alt-[" = "tab.prev";
          "alt-shift-n" = "tab.prev";
          "ctrl-shift-pagedown" = "space.next";
          "ctrl-shift-pageup" = "space.prev";
          "alt-down" = "agent.next";
          "alt-up" = "agent.prev";
          "ctrl-shift-/" = "app.help";
          "ctrl-shift-?" = "app.help";
          "ctrl-shift-b" = "layout.toggle:sidebar";
          "ctrl-shift-n" = "space.new";
          "alt-shift-c" = "space.new";
          "ctrl-shift-t" = "tab.new";
          "ctrl-shift-k" = "mod.open:creeper-picker";
          "ctrl-shift-p" = "app.palette";
          "ctrl-," = "app.settings";
          "alt-," = "app.settings";
          "ctrl-shift-o" = "mod.open:bsp";
          "alt-enter" = "mod.open:bsp";
          "ctrl-shift-e" = "pane.split:down";
          "ctrl-shift-w" = "tab.close";
          "ctrl-shift-x" = "pane.close";
          "ctrl-shift-z" = "pane.zoom";
          "ctrl-shift-l" = "layout.switch";
          "f2" = "tab.rename";
          "shift-f2" = "space.rename";
        }
        // bind "mod.open:creeper-picker" [
          "alt-p"
          "alt-t"
          "alt-s"
          "alt-w"
        ]
        // bind "pane.split:down" [
          "alt-h"
          "alt--"
        ]
        // bind "tab.rename" [
          "alt-r"
          "alt-shift-t"
        ]
        // {
          "alt-d" = "window.close";
          "alt-q" = "pane.close";
        };

        # ctrl-left and ctrl-right stay out, so pane.go wins in terminals.
        terminal = {
          "ctrl-backspace" = builtins.fromJSON ''"send:\u0017"'';
          "ctrl-shift-c" = "terminal.copy";
          "ctrl-shift-v" = "terminal.paste";
          "ctrl-v" = "terminal.paste_image";
          "ctrl-insert" = "terminal.copy";
          "shift-insert" = "terminal.paste";
        };
      };
    };
}
