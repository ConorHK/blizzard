{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [ inputs.stylix.nixosModules.stylix ];
    stylix = {
      enable = true;
      targets.gnome.enable = false;
    };
  };

  flake.modules.homeManager.theme =
    { config, ... }:
    {
      imports = [ inputs.stylix.homeModules.stylix ];
      stylix.enable = true;
      gtk.gtk4.theme = config.gtk.theme;
    };
}
