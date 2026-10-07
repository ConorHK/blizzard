{ lib, ... }:
{
  # Native modules make hashes per-system.
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.herdr-web-ui =
        let
          inherit (pkgs) bun nodejs;
          version = "0.3.52";

          src = pkgs.fetchFromGitHub {
            owner = "devswha";
            repo = "herdr-web-ui";
            tag = "v${version}";
            hash = "sha256-e0jrgCKDitGI01CM42cZUPqS83jpkZ5LygdMycSjetY=";
          };

          # Full deps build; production deps run.
          nodeModules = pkgs.stdenvNoCC.mkDerivation {
            pname = "herdr-web-ui-node-modules";
            inherit version src;

            nativeBuildInputs = [ bun ];
            dontConfigure = true;
            dontFixup = true;

            buildPhase = ''
              runHook preBuild
              export HOME=$TMPDIR
              export BUN_INSTALL_CACHE_DIR=$TMPDIR/bun-cache
              flags="--frozen-lockfile --ignore-scripts --no-progress --os=linux --cpu=x64"
              bun install $flags
              mv node_modules build
              bun install $flags --production
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              mv build $out/build
              mv node_modules $out/runtime
              runHook postInstall
            '';

            outputHashMode = "recursive";
            outputHash = "sha256-Y74x22/qbFwOvO/Ex9qsxrH73dQoC1tirldZ9CSRyb8=";
          };
        in
        pkgs.stdenv.mkDerivation {
          pname = "herdr-web-ui";
          inherit version src;

          nativeBuildInputs = [
            bun
            nodejs
            pkgs.autoPatchelfHook
            pkgs.makeWrapper
          ];
          # node-pty ships a prebuilt addon.
          buildInputs = [ pkgs.stdenv.cc.cc.lib ];

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            cp -R ${nodeModules}/build node_modules
            chmod -R u+w node_modules
            patchShebangs node_modules
            bun run build
            runHook postBuild
          '';

          # Herdr skips the shell; pin bun.
          installPhase = ''
            runHook preInstall
            root=$out/share/herdr-web-ui
            mkdir -p $root
            cp -R dist server shared scripts herdr-plugin.toml package.json $root/
            cp -R ${nodeModules}/runtime $root/node_modules
            makeWrapper ${lib.getExe bun} $out/bin/herdr-web-ui-bun \
              --prefix PATH : ${lib.makeBinPath [ nodejs ]}
            substituteInPlace $root/herdr-plugin.toml \
              --replace-fail 'command = ["bun", "scripts/plugin.ts"' \
                "command = [\"$out/bin/herdr-web-ui-bun\", \"scripts/plugin.ts\""
            runHook postInstall
          '';

          meta = {
            description = "Browser and phone client for herdr";
            homepage = "https://github.com/devswha/herdr-web-ui";
            license = lib.licenses.mit;
            platforms = [ "x86_64-linux" ];
          };
        };
    };
}
