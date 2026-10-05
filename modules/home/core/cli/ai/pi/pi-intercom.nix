{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pi-intercom = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-intercom";
        version = "0.16.1";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-intercom/-/pi-intercom-${version}.tgz";
          hash = "sha512-LhNm2JgittzbvxLSjT+fB9RIEWgJpeBSrnL5O8rfPd60SgAph5VcJWrfd5GrI0GHtSELKnw0yjjyZfcPWTaD9w==";
        };
        dontConfigure = true;
        dontBuild = true;
        # Node 24 strips types; tsx not needed.
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
          substituteInPlace $out/config.ts \
            --replace-fail 'brokerCommand: "npx",' 'brokerCommand: "${lib.getExe' pkgs.nodejs-slim "node"}",' \
            --replace-fail 'brokerArgs: ["--no-install", "tsx"],' 'brokerArgs: [],'
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.intercom.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-intercom package.";
      };

      config = lib.mkIf config.programs.pi.intercom.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-intercom}" ];
      };
    };
}
