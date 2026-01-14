{
  flake.modules.homeManager.network-manager =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.networkmanagerapplet
      ];
      wayland.windowManager.hyprland.settings = {
        windowrule = [
          "float on, match:class nm-connection-editor"
          "center on, match:class nm-connection-editor"
        ];
      };
      programs.waybar.settings.main.network.on-click =
        "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
    };
}
