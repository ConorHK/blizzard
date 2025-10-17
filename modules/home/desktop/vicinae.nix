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
        WantedBy = [ "default.target" ];
      };
      };
      services.vicinae = {
        enable = true;
        autoStart = true;
        settings = {
          font = {
            size = 10;
            normal = "Lexend";
          };
          keybinding = "defaut";
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
