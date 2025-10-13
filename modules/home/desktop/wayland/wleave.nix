{
  flake.modules.homeManager.wleave =
    { pkgs, ... }:
    {
      wayland.windowManager.hyprland.settings.bind = [
        "SUPER, x, exec, wleave"
      ];

      programs.wleave = {
        enable = true;
        settings = {
          close-on-lost-focus = true;
          buttons = [
            {
              label = "lock";
              action = "hyprlock";
              text = "Lock";
              keybind = "l";
              icon = "${pkgs.wleave}/share/wleave/icons/lock.svg";
            }
            {
              label = "hibernate";
              action = "systemctl hibernate";
              text = "Hibernate";
              keybind = "h";
              icon = "${pkgs.wleave}/share/wleave/icons/hibernate.svg";
            }
            {
              label = "logout";
              action = "loginctl terminate-user $USER";
              text = "Logout";
              keybind = "L";
              icon = "${pkgs.wleave}/share/wleave/icons/logout.svg";
            }
            {
              label = "shutdown";
              action = "systemctl poweroff";
              text = "Shutdown";
              keybind = "S";
              icon = "${pkgs.wleave}/share/wleave/icons/shutdown.svg";
            }
            {
              label = "suspend";
              action = "systemctl suspend";
              text = "Suspend";
              keybind = "s";
              icon = "${pkgs.wleave}/share/wleave/icons/suspend.svg";
            }
            {
              label = "reboot";
              action = "systemctl reboot";
              text = "Reboot";
              keybind = "r";
              icon = "${pkgs.wleave}/share/wleave/icons/reboot.svg";
            }
          ];
        };
      };
    };
}
