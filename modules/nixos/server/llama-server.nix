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
          hf-repo = "unsloth/Qwen3-4B-Instruct-2507-GGUF:Q4_K_M";
          alias = "qwen3-4b";
          ctx-size = 16384;
          n-gpu-layers = 99;
          flash-attn = "on";
          cache-type-k = "q8_0";
          cache-type-v = "q8_0";
          jinja = true;
          temp = 0.7;
          top-p = 0.8;
          top-k = 20;
          min-p = 0;
        };
      };

      systemd.services.llama-cpp = {
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
      };
    };
}
