{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      pi-btw = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-btw";
        version = "0.7.1";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-btw/-/pi-btw-${version}.tgz";
          hash = "sha512-XVHTwc6QNYHEXvdobqbUrlkvoEo/pq3pWgq4OPT/BMiyjZpjlhUW/aBO+NjFdyu1app9QL8kyGP+tsB18S1GqA==";
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
      options.programs.pi.btw.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-btw package.";
      };

      config = lib.mkIf config.programs.pi.btw.enable {
        # Package entry: loads manifest extensions and skills.
        programs.pi.settings.packages = [ "${pi-btw}" ];
      };
    };
}
