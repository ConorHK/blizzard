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

      services.hyprpaper = {
        enable = true;
        settings = {
          ipc = "on";
          splash = false;
          preload = lib.mkDefault [
            "${inputs.self.packages.${pkgs.system}.wallpapers}/wallpapers/hashwall.png"
          ];
          wallpaper = lib.mkDefault [
            ",tile:${inputs.self.packages.${pkgs.system}.wallpapers}/wallpapers/hashwall.png"
          ];
        };
      };
    };
}
