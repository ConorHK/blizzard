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

          localConf = ''
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
            <fontconfig>
              <!-- Add Symbols Nerd Font as a global fallback -->
              <match target="pattern">
                <test name="family" compare="not_eq">
                  <string>Symbols Nerd Font</string>
                </test>
                <edit name="family" mode="append">
                  <string>Symbols Nerd Font</string>
                </edit>
              </match>
            </fontconfig>
          '';
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
