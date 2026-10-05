{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      deps = {
        "@typesafe-ai/sdk" = {
          version = "0.6.0";
          hash = "sha512-IddX+Q0XM+VagOUZFeP7wZjaO4SHMdvnh2zEBdrZZnXedWI3BNK1lKhMx3ayrkFWvVLbVcUHJy6AVZlY+e6Jaw==";
        };
        "@xterm/addon-serialize" = {
          version = "0.13.0";
          hash = "sha512-kGs8o6LWAmN1l2NpMp01/YkpxbmO4UrfWybeGu79Khw5K9+Krp7XhXbBTOTc3GJRRhd6EmILjpR8k5+odY39YQ==";
        };
        "@xterm/headless" = {
          version = "5.5.0";
          hash = "sha512-5xXB7kdQlFBP82ViMJTwwEc3gKCLGKR/eoxQm4zge7GPBl86tCdI0IdPJjoKd8mUSFXz5V7i/25sfsEkP4j46g==";
        };
        re2js = {
          version = "2.8.6";
          hash = "sha512-xLgQil4kIUCrAzVk9fRSkxkFNwmygLFjVxXrLc65aE1F0+Zsb8rxumFBy4XKyvgMCTL6kilDq3EZ0piE2dP/Dg==";
        };
        # Ships prebuilt pty bindings; needs glibc 2.14.
        zigpty = {
          version = "0.1.6";
          hash = "sha512-0B+6Xa4mKgyTNMq87HoGEUb30jQ08DZLEshSlgXPvUv+GB3E0zuTM+IUuYqe0CiaZyaZvCyx9snvGqxIKhl0sA==";
        };
      };
      depSrcs = lib.mapAttrs (
        name:
        { version, hash }:
        pkgs.fetchurl {
          url = "https://registry.npmjs.org/${name}/-/${baseNameOf name}-${version}.tgz";
          inherit hash;
        }
      ) deps;
      pi-interactive-shell = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-interactive-shell";
        version = "0.17.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-interactive-shell/-/pi-interactive-shell-${version}.tgz";
          hash = "sha512-GRNitYwNpJMG8Kcg9heaD//4aT6taWyCt1ZOkvhgCFI/zPkpARJ8nefrX2URHG5RytRAvss09ZsTg7rM5NaPDQ==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
        ''
        + lib.concatStrings (
          lib.mapAttrsToList (name: tgz: ''
            mkdir -p $out/node_modules/${name}
            tar xzf ${tgz} -C $out/node_modules/${name} --strip-components=1
          '') depSrcs
        )
        + ''
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.interactiveShell.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-interactive-shell package.";
      };

      config = lib.mkIf config.programs.pi.interactiveShell.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-interactive-shell}" ];
      };
    };
}
