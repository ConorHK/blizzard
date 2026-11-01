{ lib, ... }:
{
  perSystem =
    { pkgs, self', ... }:
    let
      meta = {
        homepage = "https://herdr.dev";
        license = lib.licenses.asl20;
        platforms = [ "x86_64-linux" ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    in
    {
      packages = {
        herdr-core = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "herdr-core";
          version = "0.1.17";

          src = pkgs.fetchurl {
            url = "https://releases.herdr.dev/core/${finalAttrs.version}/herdr-core-linux-x86_64.tar.gz";
            hash = "sha256-guxEBD9olL/bcWuXm4fNpD/X+kawEE57e9k+ZNGpuHc=";
          };
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

        herdr-app = pkgs.stdenv.mkDerivation (finalAttrs: {
          pname = "herdr-app";
          version = "0.1.12";

          src = pkgs.fetchurl {
            url = "https://releases.herdr.dev/app/${finalAttrs.version}/herdr-app-linux-x86_64.tar.gz";
            hash = "sha256-omXmySXEh0WEBnQf+gnS+g09S9QBo07YwBwzYQjlfB8=";
          };

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

          meta = meta // {
            description = "Desktop app for terminals and coding agents";
            mainProgram = "herdr-app";
          };
        });
      };
    };
}
