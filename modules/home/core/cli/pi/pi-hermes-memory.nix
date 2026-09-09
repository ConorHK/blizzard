{
  flake.modules.homeManager.pi-hermes-memory =
    { pkgs, ... }:
    let
      # Pure-JS deps only; compiled pi is Bun and
      # the extension falls back to bun:sqlite itself.
      pi-hermes-memory = pkgs.stdenvNoCC.mkDerivation rec {
        pname = "pi-hermes-memory";
        version = "0.9.8";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-hermes-memory/-/pi-hermes-memory-${version}.tgz";
          hash = "sha256-Fg8Sd384y6joyVcRdDtINUcyCywfV/btrL29Z9ZWrhk=";
        };
        stripAnsi = pkgs.fetchurl {
          url = "https://registry.npmjs.org/strip-ansi/-/strip-ansi-7.2.0.tgz";
          hash = "sha256-L6Ad6GpQIu8ydzq7xOhKU6HF0x9aXL8D7SV18QQIVD8=";
        };
        ansiRegex = pkgs.fetchurl {
          url = "https://registry.npmjs.org/ansi-regex/-/ansi-regex-6.2.2.tgz";
          hash = "sha256-50a7j13YgF3EDDmbkaSiMtt9n5P+LYO3canKzntSMdc=";
        };
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/node_modules/strip-ansi $out/node_modules/ansi-regex
          tar xzf $src -C $out --strip-components=1
          tar xzf $stripAnsi -C $out/node_modules/strip-ansi --strip-components=1
          tar xzf $ansiRegex -C $out/node_modules/ansi-regex --strip-components=1
          rm -rf $out/docs
          runHook postInstall
        '';
      };
    in
    {
      programs.pi.extensionDirs.hermes-memory = pi-hermes-memory;
    };
}
