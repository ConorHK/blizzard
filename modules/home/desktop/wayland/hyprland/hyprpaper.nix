{
  flake.modules.homeManager.hyprpaper =
    {
      inputs,
      pkgs,
      lib,
      ...
    }:
    {
      stylix.targets.hyprpaper.enable = lib.mkForce false;

      wayland.windowManager.hyprland.settings.exec-once = [
        "systemctl --user start hyprpaper"
      ];

      services.hyprpaper = {
        enable = true;
        settings = {
          ipc = "on";
          splash = false;
          preload = lib.mkDefault [
            "${(inputs.self or inputs.blizzard).packages.${pkgs.system}.wallpapers}/wallpapers/hashwall.png"
          ];
          wallpaper = lib.mkDefault [
            ",tile:${
              (inputs.self or inputs.blizzard).packages.${pkgs.system}.wallpapers
            }/wallpapers/hashwall.png"
          ];
        };
      };
    };
}
