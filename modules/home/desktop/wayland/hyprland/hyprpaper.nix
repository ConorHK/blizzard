{
  flake.modules.homeManager.hyprpaper =
    {
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
          ipc = true;
          splash = false;
          wallpaper = lib.mkDefault [
            {
              monitor = "";
              path = "${pkgs.wallpapers}/wallpapers/hashwall.png";
              fit_mode = "tile";
            }
          ];
        };
      };
    };
}
