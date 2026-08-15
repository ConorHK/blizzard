{
  hyprland.lua.vicinae = ''
    hl.bind("SUPER + Space", hl.dsp.exec_cmd("vicinae toggle"))
  '';

  flake.modules.homeManager.vicinae =
    {
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
    in
    {
      # TODO: bisect and find why this causes infinite recursion
      stylix.targets.vicinae.enable = false;
      home.packages = [ pkgs.pulseaudio ];
      programs.vicinae = {
        enable = true;
        systemd = {
          enable = true;
          autoStart = true;
        };
        extensions = genRaycastExtensions [
          "tailscale"
          "google-translate"
          "spotify-player"
          "bitwarden"
        ];
        settings = {
          providers."@samlinville/tailscale".preferences.tailscalePath =
            "/run/current-system/sw/bin/tailscale";
          providers."@gebeto/translate".preferences.lang2 = "es";
          pop_to_root_on_close = true;
          close_on_focus_loss = true;
          escape_key_behavior = "navigate_back";
          launcher_window = {
            opacity = 1;
            layer_shell = {
              keyboard_interactivity = "exclusive";
              # Vicinae defaults to the 'top' layer, which Hyprland renders
              # *below* fullscreen windows - so fullscreen games hide the
              # launcher. 'overlay' renders above fullscreen.
              layer = "overlay";
            };
          };
        };
      };
    };
}
