{
  perSystem =
    { pkgs, ... }:
    {
      packages.bitbang = pkgs.buildGoModule (finalAttrs: {
        pname = "bitbang";
        version = "0.4.7";

        src = pkgs.fetchFromGitHub {
          owner = "richlegrand";
          repo = "bitbang-cli";
          tag = finalAttrs.version;
          hash = "sha256-lyPfsHc4t4foB0584p3nWTeTTHTR0G3AJ6GrwTf05ss=";
        };

        vendorHash = "sha256-Tw8TjwWoG6hMlIjPLI77jX0gBsOvgRPKN5uHgEy2cVg=";

        # Some corp networks sinkhole proxy.golang.org
        overrideModAttrs = old: {
          preBuild = (old.preBuild or "") + ''
            export GOPROXY=direct
          '';
        };

        subPackages = [ "cmd/bitbang" ];

        env.CGO_ENABLED = 0;

        meta = {
          description = "P2P remote shell, file transfer, and web proxy over WebRTC";
          homepage = "https://github.com/richlegrand/bitbang-cli";
          license = pkgs.lib.licenses.mit;
          mainProgram = "bitbang";
        };
      });
    };
}
