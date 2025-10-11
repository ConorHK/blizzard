{
  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      inputs,
      ...
    }:
    let
      creeper = inputs.self.packages.${pkgs.system}.creeper;
    in
    {
      fonts = {
        packages = [
          creeper
          pkgs.lexend
        ];
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
          package = creeper;
          name = "Creeper";
        };

        emoji = {
          package = pkgs.google-fonts;
          name = "Noto Color Emoji";
        };
      };
    };
  flake.modules.homeManager.desktop = {
    fonts.fontconfig.enable = true;
  };
}
