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
      # Try pkgs first (for downstream with overlay), fallback to inputs.self.packages (for blizzard itself)
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) creeper;
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) gohu;
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) gohu-otb;
    in
    {
      fonts = {
        packages = [
          creeper
          gohu
          pkgs.lexend
          pkgs.nerd-fonts.symbols-only
          pkgs.siji
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
            <!-- fonts.packages would cache before these edits -->
             <dir>${gohu-otb}/share/fonts</dir>
            <!-- Kitty only loads scalable fonts: https://github.com/kovidgoyal/kitty/issues/97 -->
             <match target="scan">
              <test name="family">
                <string>GohuOTB</string>
              </test>
              <edit name="spacing"><int>100</int></edit>
              <edit name="scalable"><bool>true</bool></edit>
              <edit name="outline"><bool>true</bool></edit>
             </match>
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
          package = gohu;
          name = "gohu";
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };
    };
  flake.modules.homeManager.desktop = {
    fonts.fontconfig.enable = true;
  };
}
