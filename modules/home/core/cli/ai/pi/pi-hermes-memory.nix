{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Node pi needs native better-sqlite3.
      sqlitePrebuild =
        {
          x86_64-linux = "linux-x64";
          aarch64-linux = "linux-arm64";
          aarch64-darwin = "darwin-arm64";
          x86_64-darwin = "darwin-x64";
        }
        .${pkgs.stdenv.hostPlatform.system};
      pi-hermes-memory = pkgs.stdenv.mkDerivation rec {
        pname = "pi-hermes-memory";
        version = "0.9.9";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/pi-hermes-memory/-/pi-hermes-memory-${version}.tgz";
          hash = "sha256-ahtx36NPQLumNypPcd7FTM52vkrlWSPTuD6/wcWSDCA=";
        };
        stripAnsi = pkgs.fetchurl {
          url = "https://registry.npmjs.org/strip-ansi/-/strip-ansi-7.2.0.tgz";
          hash = "sha256-L6Ad6GpQIu8ydzq7xOhKU6HF0x9aXL8D7SV18QQIVD8=";
        };
        ansiRegex = pkgs.fetchurl {
          url = "https://registry.npmjs.org/ansi-regex/-/ansi-regex-6.2.2.tgz";
          hash = "sha256-50a7j13YgF3EDDmbkaSiMtt9n5P+LYO3canKzntSMdc=";
        };
        betterSqlite3 = pkgs.fetchurl {
          url = "https://registry.npmjs.org/better-sqlite3/-/better-sqlite3-13.0.3.tgz";
          hash = "sha512-RbOBxmLBG8uvFUc15X9+9SFemKcQ0WBuISBVkpuiaUB2qblC8UWlHEjdWVoZ8AdhSwmoEgsiXKfopX0CQxaACQ==";
        };
        # Mach-O prebuilds need no interpreter rewriting, and autoPatchelfHook
        # does not run on darwin.
        nativeBuildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
        buildInputs = lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.stdenv.cc.cc.lib;
        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;
        installPhase = ''
          runHook preInstall
          mkdir -p $out/node_modules/{strip-ansi,ansi-regex,better-sqlite3}
          tar xzf $src -C $out --strip-components=1
          tar xzf $stripAnsi -C $out/node_modules/strip-ansi --strip-components=1
          tar xzf $ansiRegex -C $out/node_modules/ansi-regex --strip-components=1
          tar xzf $betterSqlite3 -C $out/node_modules/better-sqlite3 --strip-components=1
          (
            cd $out/node_modules/better-sqlite3
            # N-API prebuild: any node major loads it.
            rm -rf deps src binding.gyp
            find prebuilds -type f ! -name '${sqlitePrebuild}.node' -delete
          )
          rm -rf $out/docs
          runHook postInstall
        '';
      };
    in
    {
      options.programs.pi.hermesMemory.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the hermes-memory extension.";
      };

      config = lib.mkIf config.programs.pi.hermesMemory.enable {
        programs.pi.extensionDirs.hermes-memory = pi-hermes-memory;
      };
    };
}
