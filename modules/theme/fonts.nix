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
          # temp: track https://github.com/nixos/nixpkgs/issues/449657
          localConf = ''
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
            <fontconfig>
              <description>Accept bitmap fonts</description>
            <!-- Accept bitmap fonts -->
             <selectfont>
              <acceptfont>
               <pattern>
                 <patelt name="outline"><bool>false</bool></patelt>
               </pattern>
              </acceptfont>
             </selectfont>
            </fontconfig>
          '';
        };
      };

      stylix.fonts = {
        sizes = {
          terminal = 10;
        };

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
          package = pkgs.noto-fonts-emoji;
          name = "Noto Color Emoji";
        };
      };
    };
  flake.modules.homeManager.desktop = {
    fonts.fontconfig.enable = true;
  };
}
