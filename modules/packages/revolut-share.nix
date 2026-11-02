{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      packages.revolut-share =
        let
          buildToolsVersion = "37.0.0";
          platform = "37.0";
          minSdk = "26";

          # Kept out of the global allowlist, whose names would match far more than the SDK.
          androidPkgs = import inputs.nixpkgs {
            inherit system;
            config = {
              android_sdk.accept_license = true;
              allowUnfreePredicate =
                pkg:
                builtins.elem (lib.removePrefix "android-sdk-" (lib.getName pkg)) [
                  "build-tools"
                  "cmake"
                  "cmdline-tools"
                  "platforms"
                  "platform-tools"
                  "tools"
                ];
            };
          };
          sdk = "${
            (androidPkgs.androidenv.composeAndroidPackages {
              platformVersions = [ platform ];
              buildToolsVersions = [ buildToolsVersion ];
              includeNDK = false;
              includeEmulator = false;
              includeSystemImages = false;
            }).androidsdk
          }/libexec/android-sdk";
          buildTools = "${sdk}/build-tools/${buildToolsVersion}";
          androidJar = "${sdk}/platforms/android-${platform}/android.jar";

          apk = pkgs.stdenvNoCC.mkDerivation {
            pname = "revolut-share-apk";
            version = "0.2.0";
            src = ./revolut-share;
            nativeBuildInputs = [
              pkgs.jdk21_headless
              pkgs.zip
            ];
            buildPhase = ''
              runHook preBuild
              ${buildTools}/aapt2 link -o base.apk --manifest AndroidManifest.xml \
                -I ${androidJar} --min-sdk-version ${minSdk} --target-sdk-version 34 \
                --version-code 2 --version-name $version
              javac --release 17 -classpath ${androidJar} -d classes $(find src -name '*.java')
              ${buildTools}/d8 --release --min-api ${minSdk} --lib ${androidJar} \
                --output . $(find classes -name '*.class')
              zip -j base.apk classes.dex
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out
              ${buildTools}/zipalign -p -f 4 base.apk $out/revolut-share-unsigned.apk
              runHook postInstall
            '';
          };
        in
        # Signing with the local debug key keeps reinstalls working without a key in git.
        pkgs.writeShellApplication {
          name = "revolut-share-install";
          runtimeInputs = [
            pkgs.android-tools
            pkgs.jdk21_headless
          ];
          text = ''
            keystore="''${ANDROID_KEYSTORE:-$HOME/.android/debug.keystore}"
            if [ ! -f "$keystore" ]; then
              keytool -genkeypair -keystore "$keystore" -storepass android -alias androiddebugkey \
                -keypass android -keyalg RSA -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
            fi
            out=$(mktemp --suffix .apk)
            trap 'rm -f "$out"' EXIT
            ${buildTools}/apksigner sign --ks "$keystore" --ks-pass pass:android \
              --out "$out" ${apk}/revolut-share-unsigned.apk
            # -d picks the USB phone over network devices like the Shield.
            if [ -n "''${ANDROID_SERIAL:-}" ]; then adb install -r "$out"; else adb -d install -r "$out"; fi
          '';
          passthru = { inherit apk; };
        };
    };
}
