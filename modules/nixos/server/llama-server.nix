{
  flake.modules.nixos.llama-server =
    { lib, pkgs, ... }:
    let
      # CUDA 13 dropped Pascal, so the GTX 1060 (sm_61) needs CUDA 12.
      package =
        (pkgs.llama-cpp.override {
          cudaSupport = true;
          cudaPackages = pkgs.cudaPackages_12;
        }).overrideAttrs
          (old: {
            cmakeFlags = old.cmakeFlags ++ [ (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" "61") ];
          });
    in
    {
      services.llama-cpp = {
        enable = true;
        inherit package;
        settings = {
          host = "127.0.0.1";
          port = 11435;
          hf-repo = "unsloth/granite-4.1-3b-GGUF:Q4_K_M";
          alias = "local";
          ctx-size = 32768;
          n-gpu-layers = 99;
          flash-attn = "on";
          cache-type-k = "q8_0";
          cache-type-v = "q8_0";
          jinja = true;
          temp = 0.2;
        };
      };

      systemd.services.llama-cpp = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
}
