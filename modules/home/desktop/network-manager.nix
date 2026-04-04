{
  flake.modules.homeManager.network-manager =
    { pkgs, ... }:
    {
      programs.waybar.settings.main.network.on-click =
        "${pkgs.alacritty}/bin/alacritty --class alacritty-popup -e ${pkgs.networkmanager}/bin/nmtui-connect";
    };
}
