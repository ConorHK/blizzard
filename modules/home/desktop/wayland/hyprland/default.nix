{ config, ... }:
{
  flake.modules.homeManager.hyprland =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = with config.flake.modules.homeManager; [
        hypridle
        hyprlock
        hyprpaper
        waybar
        wayland
      ];

      xdg.portal = {
        enable = true;
        config.common.default = "*";

        extraPortals = [
          pkgs.xdg-desktop-portal-hyprland
        ];

        configPackages = [
          pkgs.hyprland
        ];
      };

      home.packages = lib.attrValues {
        inherit (pkgs)
          brightnessctl
          grim
          hyprpicker
          playerctl
          slurp
          swappy
          swaybg
          wl-clipboard
          wtype
          xdg-utils
          ;
      };

      systemd.user.services.hyprland-session = {
        Unit = {
          Description = "Hyprland session marker";
          BindsTo = "graphical-session.target";
          After = "graphical-session-pre.target";
          Before = "graphical-session.target";
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
        };
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      wayland.windowManager.hyprland.settings.exec-once = [
        "systemctl --user start hyprland-session.service"
      ];

      wayland.windowManager.hyprland = {
        enable = true;
        systemd.enable = false; # conflicts with UWSM
      };
    };
}
