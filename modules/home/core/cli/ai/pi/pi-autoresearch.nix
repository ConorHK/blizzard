{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # pi bundles typebox, not @sinclair/typebox.
      typebox = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@sinclair/typebox/-/typebox-0.34.52.tgz";
        hash = "sha512-XiMQh7qqVlxZzcVD+kkGMNGMzcTrDMLWI7S4x7z1MkCkbDPrekpZXEUK0eZqZFMuHQg2a2DZOcDIh9o5v3Gonw==";
      };
      pi-autoresearch = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-autoresearch";
        version = "1.8.1";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-autoresearch/-/pi-autoresearch-${version}.tgz";
          hash = "sha512-6Z9pnW3JaNAg2vU3Fd+m3lzimqPcATppB+OM9lxrC2DuJXMsqROSNJdDBmVNHeVFybmnVqhf7BR9/sr+2aqDpw==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/node_modules/@sinclair/typebox
          tar xzf $src -C $out --strip-components=1
          tar xzf ${typebox} -C $out/node_modules/@sinclair/typebox --strip-components=1
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.autoresearch.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-autoresearch package.";
      };

      config = lib.mkIf config.programs.pi.autoresearch.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-autoresearch}" ];
      };
    };
}
