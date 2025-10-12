{ config, ... }:
{
  flake.modules.homeManager."homeConfigurations/abhartach" = {

    programs.waybar.settings.main.output = "DP-1";
    wayland.windowManager.hyprland.settings = {
      workspace = [
        "1,monitor:DP-1"
        "2,monitor:DP-1"
        "3,monitor:DP-1"
        "4,monitor:DP-1"
        "5,monitor:DP-1"
        "6,monitor:DP-1"
        "7,monitor:DP-1"
        "8,monitor:DP-1"
        "9,monitor:DP-2"
        "10,monitor:DP-2"
      ];
      monitor = [
        "DP-1,2560x1440@144.00Hz,0x0,1"
        "DP-2,2560x1440@59.95Hz,2560x0,1"
      ];
    };

    imports = with config.flake.modules.homeManager; [
      desktop
    ];
  };
}
