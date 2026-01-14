{
  flake.modules.homeManager.alacritty = {
    wayland.windowManager.hyprland.settings.bind = [
      "SUPER, Return, exec, uwsm app -- alacritty"
    ];

    wayland.windowManager.hyprland.settings = {
      windowrule = [
        "float on, match:class alacritty-popup"
        "center on, match:class alacritty-popup"
      ];
    };
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
