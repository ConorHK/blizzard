{
  flake.modules.nixos.ollama =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.ollama = {
        enable = true;
        # Pascal GPU: current ollama has no sm_61 kernels.
        package = pkgs.ollama-cpu;
        host = "127.0.0.1";
        port = 11434;
      };

      # The stock module has no declarative model loading.
      systemd.services.ollama-pull = {
        description = "Pull Ollama embedding models";
        after = [ "ollama.service" ];
        wants = [ "ollama.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          User = "ollama";
          ExecStart = "${lib.getExe config.services.ollama.package} pull nomic-embed-text";
          RemainAfterExit = true;
        };

        # No HOME in a bare unit; Models() panics without this.
        environment = {
          OLLAMA_MODELS = config.services.ollama.modelsDir;
          OLLAMA_HOST = "${config.services.ollama.host}:${toString config.services.ollama.port}";
        };
      };
    };
}
