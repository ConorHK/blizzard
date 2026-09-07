{
  hyprland.lua.kitty = ''
    hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("uwsm app -- kitty"))
  '';

  flake.modules.homeManager.kitty =
    { config, lib, ... }:
    let
      inherit (config.lib.stylix.colors.withHashtag)
        base01
        base02
        base03
        base05
        ;
    in
    {
      xdg.configFile."kitty/open-actions.conf".source = ./open-actions.conf;

      programs.kitty = {
        enable = true;
        # Title bars inherit tab colours, whose active background is the
        # terminal background; set them so the active pane reads as active.
        extraConfig = lib.mkAfter ''
          ${builtins.readFile ./kitty.conf}

          window_title_bar_active_foreground   ${base05}
          window_title_bar_active_background   ${base02}
          window_title_bar_inactive_foreground ${base03}
          window_title_bar_inactive_background ${base01}
        '';
      };
    };
}
