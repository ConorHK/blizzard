{
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
            sha256 = "sha256-9OPLzFKQ5s65CvEl1kvqBZbTAniqYygQnRTs+xAuNzE=";
            sparseCheckout = map (name: "/extensions/${name}") names;
          };
        in
        map (
          name:
          buildNpmPackage rec {
            inherit name;
            inherit (importNpmLock) npmConfigHook;
            src = raycastRepo + "/extensions/${name}";
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
              cp -r /build/.config/*/extensions/${name}/* $out/
              runHook postInstall
            '';
            npmDeps = importNpmLock { npmRoot = src; };
          }
        ) names;
    in
    {
      wayland.windowManager.hyprland.settings.bind = [
        "SUPER, Space, exec, vicinae toggle"
      ];
      # TODO: bisect and find why this causes infinite recursion
      stylix.targets.vicinae.enable = false;
      programs.vicinae = {
        enable = true;
        systemd = {
          enable = true;
          autoStart = true;
        };
        extensions = genRaycastExtensions [
          "tailscale"
        ];
        settings = {
          providers."@samlinville/tailscale".preferences.tailscalePath =
            "/run/current-system/sw/bin/tailscale";
          pop_to_root_on_close = true;
          close_on_focus_loss = true;
          launcher_window = {
            opacity = 1;
          };
        };
      };
    };
}
