{
  perSystem =
    { pkgs, ... }:
    {
      packages.herdr-flash = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
        pname = "herdr-flash";
        version = "0.4.1";

        src = pkgs.fetchFromGitHub {
          owner = "youguanxinqing";
          repo = "herdr-flash";
          tag = "v${finalAttrs.version}";
          hash = "sha256-ptMoG7lP9wvUGRyWV6POF8XG7IYpW0/s3pn42dMJrao=";
        };

        cargoHash = "sha256-ZeOPupBcEM8+NvG7/i5qIT+++vU5CnUxv5TkOVc20Jg=";

        patches = [ ./herdr-flash/join-wrapped-rows.patch ];

        # Lock tests probe owners with ps.
        nativeCheckInputs = [ pkgs.procps ];

        # Tests size frames from the build pty.
        preCheck = ''
          if [ -t 1 ]; then stty cols 80 rows 24 < /proc/self/fd/1; fi
        '';

        # Manifest runs ./bin/herdr-flash.
        postInstall = ''
          root=$out/share/herdr-flash
          mkdir -p $root/bin
          mv $out/bin/herdr-flash $root/bin/herdr-flash
          cp herdr-plugin.toml $root/
          rmdir $out/bin
        '';

        meta = {
          description = "Herdr plugin to search, select, and yank pane text";
          homepage = "https://github.com/youguanxinqing/herdr-flash";
          license = pkgs.lib.licenses.mit;
        };
      });
    };
}
