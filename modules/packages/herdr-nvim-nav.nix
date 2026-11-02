{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-nvim-nav = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "herdr-nvim-nav";
        version = "1.0.0";

        src = pkgs.fetchFromGitHub {
          owner = "aimdevlee";
          repo = "herdr-nvim-nav";
          tag = "v${finalAttrs.version}";
          hash = "sha256-2Sa10OaDgoy/Mw3lglrnmJn4RLUJv0dfU0MhXxXdnJI=";
        };

        # Manifest runs ./herdr-nvim-nav from the plugin root.
        installPhase = ''
          runHook preInstall
          root=$out/share/herdr-nvim-nav
          install -Dm755 herdr-nvim-nav $root/herdr-nvim-nav
          install -Dm644 herdr-plugin.toml $root/herdr-plugin.toml
          runHook postInstall
        '';

        passthru.vimPlugin = pkgs.vimUtils.buildVimPlugin {
          pname = "herdr-nvim-nav";
          inherit (finalAttrs) version src;
        };

        meta = {
          description = "Ctrl+hjkl across herdr panes and Neovim splits";
          homepage = "https://github.com/aimdevlee/herdr-nvim-nav";
          license = pkgs.lib.licenses.mit;
          platforms = pkgs.lib.platforms.unix;
        };
      });
    };
}
