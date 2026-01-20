{
  flake.modules.homeManager.vicinae =
    { ... }:
    {
      wayland.windowManager.hyprland.settings.bind = [
        "SUPER, Space, exec, vicinae toggle"
      ];
      # TODO: bisect and find why this causes infinite recursion
      stylix.targets.vicinae.enable = false;
      programs.vicinae = {
        enable = true;
        systemd = {
          enable = true;
          autoStart = true;
        };
        settings = {
          pop_to_root_on_close = true;
          close_on_focus_loss = true;
          launcher_window = {
            opacity = 1;
          };
        };
      };
    };
}
