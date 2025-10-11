{
  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      inputs,
      ...
    }:
    {
      fonts = {
        enableDefaultPackages = true;
        fontDir.enable = true;
        fontconfig = {
          enable = true;
          useEmbeddedBitmaps = true;
        };
      };

      stylix.fonts = {
        sansSerif = lib.mkDefault {
          package = pkgs.lexend;
          name = "Lexend";
        };

        serif = lib.mkDefault config.stylix.fonts.sansSerif;

        monospace = {
          package = inputs.self.packages.${pkgs.system}.creeper;
          name = "Creeper";
        };

        emoji = {
          package = pkgs.google-fonts;
          name = "Noto Color Emoji";
        };
      };
    };
}
