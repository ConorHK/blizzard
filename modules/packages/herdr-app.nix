{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      releases = {
        x86_64-linux = {
          target = "linux-x86_64";
          core = "sha256-guxEBD9olL/bcWuXm4fNpD/X+kawEE57e9k+ZNGpuHc=";
          app = "sha256-omXmySXEh0WEBnQf+gnS+g09S9QBo07YwBwzYQjlfB8=";
        };
        aarch64-darwin = {
          target = "macos-aarch64";
          core = "sha256-ztvU1Nm6E4VYgZjdTTxn0mVEePM63VtkRdTQ652l/PM=";
          app = "sha256-AGpPaECaeVSNGqbF+Z2okRt9FJEO8qxr0aPc5jTKXQM=";
        };
      };
      release = releases.${system};

      fetch =
        part: version:
        pkgs.fetchurl {
          url = "https://releases.herdr.dev/${part}/${version}/herdr-${part}-${release.target}.tar.gz";
          hash = release.${part};
        };

      meta = {
        homepage = "https://herdr.dev";
        license = lib.licenses.asl20;
        platforms = lib.attrNames releases;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
      appMeta = meta // {
        description = "Desktop app for terminals and coding agents";
        mainProgram = "herdr-app";
      };

      herdr-app-linux = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "herdr-app";
        version = "0.1.12";
        src = fetch "app" finalAttrs.version;

        nativeBuildInputs = [
          pkgs.autoPatchelfHook
          pkgs.copyDesktopItems
          pkgs.makeWrapper
        ];
        buildInputs = [
          pkgs.libgcc
          pkgs.libxcb
          pkgs.libxkbcommon
        ];
        # GPUI dlopens these at run time.
        runtimeDependencies = [
          pkgs.alsa-lib
          pkgs.fontconfig.lib
          pkgs.freetype
          pkgs.libGL
          pkgs.libx11
          pkgs.libxcursor
          pkgs.libxi
          pkgs.libxrandr
          pkgs.vulkan-loader
          pkgs.wayland
        ];

        desktopItems = [
          (pkgs.makeDesktopItem {
            name = "herdr-app";
            desktopName = "Herdr";
            comment = "Terminals and coding agents that keep running";
            exec = "herdr-app";
            icon = "herdr-app";
            categories = [ "Development" ];
            startupWMClass = "herdr-app";
          })
        ];

        installPhase = ''
          runHook preInstall
          install -Dm755 herdr-app $out/libexec/herdr-app
          install -Dm644 herdr-app.svg $out/share/icons/hicolor/scalable/apps/herdr-app.svg
          makeWrapper $out/libexec/herdr-app $out/bin/herdr-app \
            --suffix PATH : ${lib.makeBinPath [ self'.packages.herdr-core ]}
          runHook postInstall
        '';

        meta = appMeta;
      });

      # The signed bundle finds herdr-core on the login shell PATH, so it gets no wrapper.
      herdr-app-darwin = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "herdr-app";
        version = "0.1.12";
        src = fetch "app" finalAttrs.version;
        sourceRoot = ".";

        # Fixup strips the binary, which breaks the Apple signature.
        dontFixup = true;

        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications $out/bin
          cp -R Herdr.app $out/Applications/
          ln -s $out/Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
          runHook postInstall
        '';

        meta = appMeta;
      });
    in
    {
      packages = lib.optionalAttrs (releases ? ${system}) {
        herdr-core = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "herdr-core";
          version = "0.1.17";
          src = fetch "core" finalAttrs.version;
          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            install -Dm755 herdr-core $out/bin/herdr-core
            ln -s herdr-core $out/bin/hc
            runHook postInstall
          '';

          meta = meta // {
            description = "Server that keeps Herdr terminals and agents running";
            mainProgram = "hc";
          };
        });

        herdr-app = if pkgs.stdenv.hostPlatform.isDarwin then herdr-app-darwin else herdr-app-linux;
      };
    };
}
