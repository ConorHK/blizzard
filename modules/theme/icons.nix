{
  flake.modules.homeManager.desktop =
    { pkgs, ... }:
    {
      stylix = {
        cursor = {
          name = "Quintom_Ink";
          package = pkgs.quintom-cursor-theme;
          size = 20;
        };
        iconTheme = {
          enable = true;
          package = pkgs.tela-icon-theme;
          light = "Tela";
          dark = "Tela";
        };
      };
    };
}
