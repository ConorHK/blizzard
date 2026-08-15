{
  hyprland.lua.alacritty = ''
    hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm app -- alacritty"))
    hl.window_rule({ match = { class = "alacritty-popup" }, float = true })
    hl.window_rule({ match = { class = "alacritty-popup" }, center = true })
  '';

  flake.modules.homeManager.alacritty = {
    programs = {
      alacritty = {
        enable = true;
        settings = {
          window = {
            padding = {
              x = 5;
              y = 5;
            };
            decorations_theme_variant = "Dark";
          };
          cursor = {
            style = "block";
            unfocused_hollow = true;
          };
        };
      };
    };
  };
}
