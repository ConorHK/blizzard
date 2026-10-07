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
      herdr-nvim = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-nvim;
    in
    {
      home.packages = [
        pkgs.herdr
        herdr-nvim
      ];

      # Herdr rewrites plugins.json, so link it.
      home.activation.herdrNvim = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run --quiet ${lib.getExe pkgs.herdr} plugin link ${herdr-nvim}/share/herdr-nvim \
          || warnEcho "herdr plugin link failed for herdr-nvim"
      '';

      xdg.configFile."herdr/config.toml".source = (pkgs.formats.toml { }).generate "herdr.toml" {
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
          ];
        };
      };
    };
}
