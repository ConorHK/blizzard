{
  perSystem =
    { pkgs, ... }:
    {
      packages.zvec-grep = pkgs.buildNpmPackage rec {
        pname = "zvec-grep";
        version = "0.2.2";

        src = pkgs.fetchFromGitHub {
          owner = "zvec-ai";
          repo = "zvec-grep";
          tag = "v${version}";
          sha256 = "sha256-TDEK7ioPJWShJr5Ch3S6ObwgKqNnP8p9JTWYE2QZ3Z4=";
        };

        inherit (pkgs) nodejs;

        npmDepsHash = "sha256-ykSQ5aTt/pgow6GIJAZ6Vo8MqasrLhtKAagHcQgdI4s=";

        env.ONNXRUNTIME_NODE_INSTALL_CUDA = "skip";

        doInstallCheck = true;

        meta = {
          description = "Agent-friendly hybrid workspace search across code and non-code content";
          homepage = "https://github.com/zvec-ai/zvec-grep";
          license = pkgs.lib.licenses.asl20;
          mainProgram = "zg";
        };
      };
    };
}
