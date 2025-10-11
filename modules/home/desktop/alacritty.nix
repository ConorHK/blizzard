{
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
