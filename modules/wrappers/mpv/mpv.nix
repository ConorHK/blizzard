{
  flake.wrappers.mpv =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.mpv.override {
        # mpris needs D-Bus, which only Linux has.
        scripts = lib.filter (lib.meta.availableOn pkgs.stdenv.hostPlatform) (
          lib.attrValues {
            inherit (pkgs.mpvScripts)
              uosc
              mpris
              autoload
              ;
          }
        );
      };
      flagSeparator = "=";
      # --config-dir would also put mpv's watch-later state in the store.
      flags."--include" = ./mpv.conf;

      wrapperVariants = {
        # nixpkgs points umpv at its own mpv, which never sees the include.
        umpv = {
          mirror = false;
          package = config.package.unwrapped;
          env.MPV = config.wrapperPaths.placeholder;
        };
        # The Dock and Spotlight start the bundle's own executable, not bin/mpv.
        mpv = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          wrapperImplementation = "binary";
          exePath = "Applications/mpv.app/Contents/MacOS/mpv";
          binDir = "Applications/mpv.app/Contents/MacOS";
        };
      };
    };
}
