{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pi-messenger = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-messenger";
        version = "0.15.2";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-messenger/-/pi-messenger-${version}.tgz";
          hash = "sha512-GcoI/FaI98dl+ZQq54W8VnCZ0kuR0VaJMu4myOh3awddOD6A/0hRU+ALzy//Jdixsol0ANQWpvyFphS4It9kiQ==";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          tar xzf $src -C $out --strip-components=1
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.messenger.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-messenger package.";
      };

      config = lib.mkIf config.programs.pi.messenger.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-messenger}" ];
      };
    };
}
