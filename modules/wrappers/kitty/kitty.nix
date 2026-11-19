{
  flake.wrappers.kitty =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      # Kitty looks for kittens, watchers and open-actions.conf beside kitty.conf.
      configDir =
        pkgs.runCommand "kitty-config"
          {
            src = builtins.path {
              path = ./config;
              name = "kitty-config-src";
            };
            inherit (config) extraConfig;
            passAsFile = [ "extraConfig" ];
          }
          ''
            mkdir $out
            cp $src/* $out/
            chmod u+w $out/kitty.conf
            cat "$extraConfigPath" >> $out/kitty.conf
          '';
    in
    {
      imports = [ wlib.modules.default ];

      options.extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Lines added after the shared kitty.conf, for one host's settings.";
      };

      config = {
        package = pkgs.kitty;
        env.KITTY_CONFIG_DIRECTORY = "${configDir}";

        # The Dock and Spotlight start the bundle's own executable, not bin/kitty.
        wrapperVariants.kitty = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          wrapperImplementation = "binary";
          mirror = false;
          package = placeholder "out";
          exePath = lib.removePrefix "/" config.wrapperPaths.relPath;
          binDir = "Applications/kitty.app/Contents/MacOS";
        };
      };
    };
}
