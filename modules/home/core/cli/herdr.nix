{ inputs, ... }:
{
  flake.modules.homeManager.core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system})
        herdr-nvim
        herdr-flash
        herdr-radar
        ;
      toml = pkgs.formats.toml { };
      radarId = "hhdebb.herdr-radar";
      radarSettings = toml.generate "herdr-radar.toml" {
        variant = "none";
        follow_appearance = false;
        render_hook = "${./herdr-radar-hook.js}";
      };
    in
    {
      home = {
        packages = [
          pkgs.herdr
          herdr-nvim
        ];

        activation = {
          # Herdr rewrites plugins.json, so link it.
          herdrNvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run --quiet ${lib.getExe pkgs.herdr} plugin link ${herdr-nvim}/share/herdr-nvim \
              || warnEcho "herdr plugin link failed for herdr-nvim"
          '';
          herdrFlash = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run --quiet ${lib.getExe pkgs.herdr} plugin link ${herdr-flash}/share/herdr-flash \
              || warnEcho "herdr plugin link failed for herdr-flash"
          '';
          herdrRadar = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            run --quiet ${lib.getExe pkgs.herdr} plugin link ${herdr-radar}/share/herdr-radar \
              || warnEcho "herdr plugin link failed for herdr-radar"
          '';
        };
      };

      xdg.configFile."herdr/plugins/config/${radarId}/config.toml".source = radarSettings;

      xdg.configFile."herdr/config.toml".source = herdr-radar.configure {
        settings = radarSettings;
        stateDir = "${config.xdg.stateHome}/herdr/plugins/${radarId}";
        base = toml.generate "herdr-base.toml" {
          # Herdr cannot write a store symlink.
          onboarding = false;
          theme.name = "terminal";
          ui.toast.delivery = "herdr";

          # Devbox PATH lists another fish first.
          terminal.default_shell = lib.getExe config.programs.fish.package;

          keys = {
            prefix = "ctrl+t";

            # Picker stands in for zellij modes.
            workspace_picker = [
              "prefix+p"
              "prefix+t"
              "prefix+s"
              "prefix+w"
            ];
            navigate_pane_left = "ctrl+h";
            navigate_pane_down = "ctrl+j";
            navigate_pane_up = "ctrl+k";
            navigate_pane_right = "ctrl+l";

            focus_pane_left = [
              "ctrl+h"
              "ctrl+left"
            ];
            focus_pane_down = [
              "ctrl+j"
              "ctrl+down"
            ];
            focus_pane_up = [
              "ctrl+k"
              "ctrl+up"
            ];
            focus_pane_right = [
              "ctrl+l"
              "ctrl+right"
            ];

            split_horizontal = [
              "prefix+h"
              "prefix+minus"
            ];
            rename_tab = [
              "prefix+r"
              "prefix+shift+t"
            ];
            previous_tab = "prefix+shift+n";
            new_workspace = "prefix+shift+c";
            copy_mode = [
              "prefix+o"
              "prefix+["
            ];
            open_notification_target = "prefix+shift+o";
            resize_mode = "prefix+shift+r";
            reload_config = "prefix+ctrl+r";
            detach = [
              "prefix+d"
              "prefix+q"
            ];
            settings = "prefix+comma";
            edit_scrollback = "prefix+shift+e";

            command = [
              {
                key = "prefix+e";
                type = "plugin_action";
                command = "chmarax.herdr-nvim.toggle";
                description = "nvim sidebar";
              }
              {
                key = "prefix+f";
                type = "plugin_action";
                command = "chmarax.herdr-nvim.pick-file";
                description = "open file in sidebar";
              }
              {
                key = "prefix+y";
                type = "plugin_action";
                command = "youguanxinqing.herdr-flash.flash";
                description = "search, select, and yank";
              }
              {
                key = "prefix+a";
                type = "plugin_action";
                command = "${radarId}.view-flip";
                description = "agents: active or recent";
              }
            ];
          };
        };
      };
    };
}
