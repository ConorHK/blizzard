{
  flake.modules.homeManager.hyprpaper =
    {
      pkgs,
      inputs,
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
              path = "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.wallpapers}/wallpapers/hashwall.png";
              fit_mode = "tile";
            }
          ];
        };
      };
    };
}
