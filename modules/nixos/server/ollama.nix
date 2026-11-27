{
  flake.modules.nixos.ollama =
    { pkgs, ... }:
    {
      services.ollama = {
        enable = true;
        # Pascal GPU: current ollama has no sm_61 kernels.
        package = pkgs.ollama-cpu;
        host = "127.0.0.1";
        port = 11434;
        loadModels = [ "nomic-embed-text" ];
      };
    };
}
