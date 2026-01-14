{
  flake.modules.homeManager.vicinae =
    { inputs, ... }:
    {
      imports = [
        inputs.vicinae.homeManagerModules.default
      ];

      wayland.windowManager.hyprland.settings.bind = [
        "SUPER, Space, exec, vicinae toggle"
      ];
      systemd.user.services.vicinae = {
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
      # TODO: bisect and find why this causes infinite recursion
      stylix.targets.vicinae.enable = false;
      services.vicinae = {
        enable = true;
        settings = {
          font = {
            size = 10;
            normal = "Lexend";
          };
          keybinding = "default";
          # keybinds = {};
          popToRootOnClose = false;
          rootSearch.searchFiles = true;
          theme.name = "vicinae-dark";

          window = {
            csd = true;
            rounding = 0;
            opacity = 1;
          };
        };
      };
    };
}
