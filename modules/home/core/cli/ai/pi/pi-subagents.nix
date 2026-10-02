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
        acorn = {
          version = "8.18.0";
          hash = "sha512-lGq+9yr1/GuAWaVYIHRjvvySG5/4VfKIvC8EWxStPdcDh/Ka7FG3twP6v4d5BkravUilhIAsG4Qj83t02LWUPQ==";
        };
        jiti = {
          version = "2.7.0";
          hash = "sha512-AC/7JofJvZGrrneWNaEnJeOLUx+JlGt7tNa0wZiRPT4MY1wmfKjt2+6O2p2uz2+skll8OZZmJMNqeke7kKbNgQ==";
        };
        undici = {
          version = "8.10.2";
          hash = "sha512-/y4/bH9YNU5hi9NIrpOuvGXFcxrj3CMrV+/AYpowAYTpHn8gX/XPFjNy766FPoYY0miQhdW977JFWKGNhBdwyQ==";
        };
        yaml = {
          version = "2.8.3";
          hash = "sha512-AvbaCLOO2Otw/lW5bmh9d/WEdcDFdQp2Z2ZUH3pX9U2ihyUY0nvLv7J6TrWowklRGPYbB/IuIMfYgxaCPg5Bpg==";
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
      pi-subagents = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-subagents";
        version = "0.74.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-subagents/-/pi-subagents-${version}.tgz";
          hash = "sha512-7+67TCpQuYoW2kMu4Kmt4j90hiR8uX8ozg3F/eakApUU6PxK7NteO58ylOWPql7fh/uTIEfS00FT2LKVDTSicw==";
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
      options.programs.pi.subagents.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-subagents package.";
      };

      config = lib.mkIf config.programs.pi.subagents.enable {
        # Package entry: loads manifest extensions, skills, prompts.
        programs.pi.settings.packages = [ "${pi-subagents}" ];
      };
    };
}
