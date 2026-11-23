{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-nvim = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "herdr-nvim";
        version = "1.3.1";

        src = pkgs.fetchFromGitHub {
          owner = "ChmaraX";
          repo = "herdr-nvim";
          tag = "v${finalAttrs.version}";
          hash = "sha256-/026mNSbhZIAMJeNdSsbi9vhUuQEfdjqI99QzKAHW6w=";
        };

        cargoHash = "sha256-YhOprgqqWHV4b2Md93BRTdKNFyCrYFV3pm6gy/hyoDk=";

        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [
          pkgs.libgit2
          pkgs.zlib
        ];
        env.LIBGIT2_NO_VENDOR = 1;

        nativeCheckInputs = [
          pkgs.gitMinimal
          pkgs.procps
        ];
        # This test walks the source as a git checkout, which the fetched tarball is not.
        checkFlags = [ "--skip=picker::tests::fff_end_to_end_over_this_repo" ];
        # The daemon tests read the process table, which no ps can do inside a macOS build.
        doCheck = pkgs.stdenv.hostPlatform.isLinux;

        # The app mods run the binary from a root that also holds the plugin's Lua.
        postInstall = ''
          cp -R lua plugin $out/
          mkdir -p $out/share/herdr-app
          cp -R herdr-app/mods herdr-app/keys.json $out/share/herdr-app/
        '';

        meta = {
          description = "Neovim beside Herdr agents, with a file tree and agent comments";
          homepage = "https://github.com/ChmaraX/herdr-nvim";
          license = pkgs.lib.licenses.mit;
          mainProgram = "herdr-nvim";
        };
      });
    };
}
