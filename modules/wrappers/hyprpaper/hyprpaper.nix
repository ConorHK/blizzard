{ inputs, ... }:
{
  flake.wrappers.hyprpaper =
    { pkgs, wlib, ... }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.hyprpaper;
      flags."--config" = pkgs.replaceVars ./hyprpaper.conf {
        inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) wallpapers;
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.hyprpaper = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
