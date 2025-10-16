{
  flake.modules.homeManager.rofi =
    { pkgs, ... }:
    {
      wayland.windowManager.hyprland.settings.bind = [
        "SUPER, Space, exec, uwsm app -- rofi -show drun -mode drun"
      ];
      programs.rofi = {
        enable = true;
        terminal = "${pkgs.alacritty}/bin/alacritty";
        extraConfig = {
          modi = "drun";
          show-icons = true;
          drun-display-format = "{name}";
          location = 0;
          disable-history = false;
          hide-scrollbar = true;
          display-drun = "Apps ";
          display-run = "Run ";
          display-window = "Window";
          display-Network = "Network";
          sidebar-mode = true;
        };
      };
    };
}
