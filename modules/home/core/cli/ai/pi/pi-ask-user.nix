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
      pi-ask-user = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-ask-user";
        version = "0.16.0";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-ask-user/-/pi-ask-user-${version}.tgz";
          hash = "sha512-IUELJJAtCNDiHMtW8QJE6vKvbmCUTZJSJddfR15gNmPymwRtNQH132EIwdMELZAkUG8EmVMIUIYVa1Z8V3TtPw==";
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
      options.programs.pi.askUser.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-ask-user package.";
      };

      config = lib.mkIf config.programs.pi.askUser.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-ask-user}" ];
      };
    };
}
