{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-nvim = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "herdr-nvim";
        version = "1.1.0";

        src = pkgs.fetchFromGitHub {
          owner = "ChmaraX";
          repo = "herdr-nvim";
          tag = "v${finalAttrs.version}";
          hash = "sha256-q44Qt73XzNNipwF3hHr3Hzg0EReC3tz2bKB/l4ZBqiE=";
        };

        cargoHash = "sha256-pImtQ1YiM47VvA8u9ER/lXtDVsZhQy38fkCbzmT/gc4=";

        # Tests need a live herdr session.
        doCheck = false;

        # Binary walks up to find lua/.
        postInstall = ''
          root=$out/share/herdr-nvim
          mkdir -p $root/bin
          mv $out/bin/herdr-nvim $root/bin/herdr-nvim
          ln -s $root/bin/herdr-nvim $out/bin/herdr-nvim
          cp -r lua plugin doc herdr-plugin.toml $root/
        '';

        passthru.vimPlugin = pkgs.vimUtils.buildVimPlugin {
          pname = "herdr-nvim";
          inherit (finalAttrs) version src;
        };

        meta = {
          description = "Neovim sidebar and agent annotations for herdr";
          homepage = "https://github.com/ChmaraX/herdr-nvim";
          license = pkgs.lib.licenses.mit;
          mainProgram = "herdr-nvim";
        };
      });
    };
}
