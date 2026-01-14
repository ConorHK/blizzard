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
          window = {
            csd = true;
            rounding = 0;
            opacity = 1;
          };
        };
      };
    };
}
