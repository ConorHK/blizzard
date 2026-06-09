{
  flake.modules.wrapper."hyprland/hyprpaper".settings.exec-once = [
    "systemctl --user start hyprpaper"
  ];

  flake.modules.homeManager.hyprpaper =
    {
      pkgs,
      lib,
      inputs,
      ...
    }:
    {
      stylix.targets.hyprpaper.enable = lib.mkForce false;

      services.hyprpaper = {
        enable = true;
        settings = {
          ipc = true;
          splash = false;
          wallpaper = lib.mkDefault [
            {
              monitor = "";
              path = "${
                inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.wallpapers
              }/wallpapers/hashwall.png";
              fit_mode = "tile";
            }
          ];
        };
      };
    };
}
