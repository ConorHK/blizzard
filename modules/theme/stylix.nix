{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [ inputs.stylix.nixosModules.stylix ];
    stylix = {
      enable = true;
      targets.gnome.enable = false;
    };
  };

  flake.modules.homeManager.theme = {
    imports = [ inputs.stylix.homeManagerModules.stylix ];
    stylix.enable = true;
  };
}
