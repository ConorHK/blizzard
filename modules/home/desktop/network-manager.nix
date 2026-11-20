{
  flake.modules.homeManager.network-manager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.waybar.settings.main.network.on-click =
        "${lib.getExe config.wrappers.alacritty.wrapper} --class alacritty-popup -e ${pkgs.networkmanager}/bin/nmtui-connect";
    };
}
