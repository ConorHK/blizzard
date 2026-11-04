{ lib, ... }:
{
  # Native modules make hashes per-system.
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.ovis =
        let
          inherit (pkgs) bun nodejs;
          version = "0.4.22";

          src = pkgs.fetchFromGitHub {
            owner = "devswha";
            repo = "ovis";
            tag = "v${version}";
            hash = "sha256-paZjOPJqmf3JLBOEoSHrJQ5IbjqFYSHPaQnLBk/IplU=";
          };

          ptySidecar = pkgs.rustPlatform.buildRustPackage {
            pname = "ovis-pty-sidecar";
            inherit version src;
            sourceRoot = "${src.name}/crates/pty-sidecar";
            cargoHash = "sha256-vin5SGninwkDlpWIK4Cc5oO4cZ7DjTXDovUpu0fWwlE=";
            meta.mainProgram = "ovis-pty-sidecar";
          };

          # Full deps build; production deps run.
          nodeModules = pkgs.stdenvNoCC.mkDerivation {
            pname = "ovis-node-modules";
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
            outputHash = "sha256-DgGdOYYiIQxKj3xliehGGByhRn6G9uLpV2frGlda6Mw=";
          };
        in
        pkgs.stdenv.mkDerivation {
          pname = "ovis";
          inherit version src;

          patches = [
            ./ovis/allowed-origin.patch
            ./ovis/no-telemetry.patch
            ./ovis/herdr-core-pi-session.patch
          ];

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
            # The sandbox has no /usr/bin/env for the .bin shim.
            bun --bun node_modules/vite/bin/vite.js build
            runHook postBuild
          '';

          # Herdr skips the shell; pin bun.
          installPhase = ''
            runHook preInstall
            root=$out/share/ovis
            mkdir -p $root/bin
            cp -R dist server shared integrations scripts herdr-plugin.toml package.json \
              CHANGELOG.md release-summaries.json $root/
            cp -R ${nodeModules}/runtime $root/node_modules
            # A link keeps autoPatchelf off the vouched bytes.
            ln -s ${lib.getExe ptySidecar} $root/bin/ovis-pty-sidecar
            printf '{"crate":null,"sha256":"%s","version":"%s"}\n' \
              "$(sha256sum ${lib.getExe ptySidecar} | cut -d' ' -f1)" ${version} \
              > $root/bin/ovis-pty-sidecar.json
            makeWrapper ${lib.getExe bun} $out/bin/ovis-bun \
              --prefix PATH : ${lib.makeBinPath [ nodejs ]}
            substituteInPlace $root/herdr-plugin.toml \
              --replace-fail '"sh", "scripts/with-bun.sh"' "\"$out/bin/ovis-bun\""
            runHook postInstall
          '';

          meta = {
            description = "Browser and phone client for herdr";
            homepage = "https://github.com/devswha/ovis";
            license = lib.licenses.mit;
            platforms = [ "x86_64-linux" ];
          };
        };
    };
}
