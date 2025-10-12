{
  flake.modules.homeManager.waybar = {

    wayland.windowManager.hyprland.settings.exec-once = [
      "systemctl --user start waybar"
    ];

    programs.waybar = {
      enable = true;
      systemd.enable = true;
      style = ''
        *{
          all: unset;
        }
      '';
      settings.main = {
        name = "sidebar";
        layer = "top";
        position = "left";
        spacing = 5;
        modules-left = [ "clock" ];
        modules-center = [
          "hyprland/workspaces"
          "niri/workspaces"
        ];
        modules-right = [
          "wireplumber"
          "network"
        ];
        "hyprland/workspaces" = {
          disable-scroll = true;
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            active = "•";
            default = "•";
          };
          persistent-workspaces = {
            "1" = [ ];
            "2" = [ ];
            "3" = [ ];
            "4" = [ ];
            "5" = [ ];
          };
          sort-by-number = true;
        };
        clock = {
          format = "{:%H\n%M\n--\n%d\n%m}";
        };
        network = {
          interval = 1;
          format = "";
          format-ethernet = "e:con";
          format-wifi = "w:con";
          format-disconnected = "n:dis";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          tooltip-format-ethernet = "{ifname}";
          tooltip-format-disconnected = "disconnected";
        };
        wireplumber = {
          format = "v:{volume}%";
          max-volume = 100;
          scroll-step = 5;
          on-click = "pavucontrol";
        };
        battery = {
          states = {
            good = 70;
            warning = 30;
            critical = 15;
          };
          format = "b:{capacity}%";
          format-charging = "c:{capacity}%";
        };
      };
    };
  };
}
