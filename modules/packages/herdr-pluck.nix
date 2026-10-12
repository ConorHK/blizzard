{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-pluck = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "herdr-pluck";
        version = "0.3.1";

        src = pkgs.fetchFromGitHub {
          owner = "rmarganti";
          repo = "herdr-pluck";
          tag = "v${finalAttrs.version}";
          hash = "sha256-QFHjKbNPuK4pNd9T1S6IlHyFfXBRik93js+1mlXZDT4=";
        };

        cargoHash = "sha256-p6KhaqawJOSwt/JfZGSKXSxa2eU570wkXEAd3j1o92Y=";

        # Herdr forwards OSC 52 to the client.
        postPatch = ''
          substituteInPlace src/clipboard/mod.rs \
            --replace-fail \
              'copy_with_runner(text, &SystemCommandRunner, ClipboardEnvironment::current())' \
              'SystemCommandRunner.run_with_stdin(tool::ClipboardTool { name: "${pkgs.lib.getExe' pkgs.oscclip "osc-copy"}", args: &[] }, text).map(|()| CopySuccess { tool: "osc-copy".into() })'
        '';

        # Manifest runs ./bin/herdr-pluck.
        postInstall = ''
          root=$out/share/herdr-pluck
          mkdir -p $root/bin
          mv $out/bin/herdr-pluck $root/bin/herdr-pluck
          cp herdr-plugin.toml $root/
          rmdir $out/bin
        '';

        meta = {
          description = "Herdr plugin that copies visible tokens via hints";
          homepage = "https://github.com/rmarganti/herdr-pluck";
          license = pkgs.lib.licenses.mit;
        };
      });
    };
}
