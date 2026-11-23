{ config, ... }:
let
  inherit (config.flake.wrappers.vicinae) install;
in
{
  hyprland.lua.vicinae = ''
    hl.bind("SUPER + Space", hl.dsp.exec_cmd("vicinae toggle"))
  '';

  flake.modules.nixos.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      rayCli = pkgs.fetchurl {
        url = "https://cli.raycast.com/1.86.0-alpha.65/linux/ray";
        sha256 = "sha256-UgDA2hIH7HwKl3j4UEGIlvh6eE+IWUlSML0wloHFPQw=";
      };
      genRaycastExtensions =
        with pkgs;
        names:
        let
          raycastRepo = fetchFromGitHub {
            owner = "raycast";
            repo = "extensions";
            rev = "c37abc83a33a8179d8276723d14c99710a25c027";
            sha256 = "sha256-wDb9+7hDavZjKqdhWAj7VWJ8P1UYnMG41eSZtkoHcFw=";
            sparseCheckout = map (name: "/extensions/${name}") names;
          };
        in
        map (
          name:
          buildNpmPackage rec {
            inherit name;
            inherit (importNpmLock) npmConfigHook;
            src = raycastRepo + "/extensions/${name}";
            # bitwarden's electron dep tries to fetch a binary at build time; no network in the sandbox.
            ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
            buildPhase = ''
              runHook preBuild
              mkdir -p node_modules/@raycast/api/bin/linux
              cp ${rayCli} node_modules/@raycast/api/bin/linux/ray
              chmod +x node_modules/@raycast/api/bin/linux/ray
              npm run build
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p $out/
              # ray build outputs under the extension's package.json name, which
              # isn't always the directory name (e.g. google-translate -> translate).
              cp -r /build/.config/*/extensions/*/* $out/
              runHook postInstall
            '';
            npmDeps = importNpmLock { npmRoot = src; };
          }
        ) names;

      extensionNames = [
        "tailscale"
        "google-translate"
        "spotify-player"
        "bitwarden"
      ];
      extensions = genRaycastExtensions extensionNames;

    in
    {
      imports = [ install ];
      wrappers.vicinae.enable = true;

      environment.systemPackages = [ pkgs.pulseaudio ];

      environment.etc = lib.listToAttrs (
        map (
          extension: lib.nameValuePair "vicinae/extensions/${extension.name}" { source = extension; }
        ) extensions
      );

      # Vicinae reads extensions from a fixed path in the home directory.
      # L never replaces one installed by hand, and the /etc targets follow each rebuild.
      systemd.user.tmpfiles.rules = [
        "d %h/.local/share/vicinae/extensions 0755 - - -"
      ]
      ++ map (
        name: "L %h/.local/share/vicinae/extensions/${name} - - - - /etc/vicinae/extensions/${name}"
      ) extensionNames;

      systemd.user.services.vicinae = {
        description = "Vicinae server daemon";
        documentation = [ "https://docs.vicinae.com" ];
        after = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        wantedBy = [ "graphical-session.target" ];
        # Launched apps inherit the session's PATH.
        enableDefaultPath = false;
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe config.wrappers.vicinae.wrapper} server";
          KillMode = "process";
          Restart = "always";
          RestartSec = 5;
        };
      };
    };
}
