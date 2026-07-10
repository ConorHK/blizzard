{
  flake.modules.nixos.voice =
    _:
    let
      dataDir = "/storage/data/voice";
      whisperPort = 10300;
      ttsPort = 10200;
    in
    {
      home-manager.users.containers.virtualisation.quadlet = {
        networks.kokoro.networkConfig = { };

        containers = {
          wyoming-whisper.containerConfig = {
            # renovate: datasource=docker depName=rhasspy/wyoming-whisper
            image = "rhasspy/wyoming-whisper:3.5.0";
            publishPorts = [ "${toString whisperPort}:${toString whisperPort}" ];
            volumes = [ "${dataDir}/whisper:/data" ];
            exec = "--model base.en --language en";
            noNewPrivileges = true;
          };

          kokoro.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/remsky/kokoro-fastapi-gpu
            image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.5.0";
            networks = [ "kokoro.network" ];
            devices = [ "nvidia.com/gpu=all" ];
            environments = {
              USE_GPU = "True";
              USE_ONNX = "True";
              ONNX_NUM_THREADS = "12";
              ONNX_INTER_OP_THREADS = "6";
              ONNX_EXECUTION_MODE = "parallel";
              ONNX_OPTIMIZATION_LEVEL = "all";
              ONNX_MEMORY_PATTERN = "True";
              ONNX_ARENA_EXTEND_STRATEGY = "kNextPowerOfTwo";
            };
          };

          wyoming-kokoro = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/roryeckel/wyoming_openai
              image = "ghcr.io/roryeckel/wyoming_openai:latest";
              publishPorts = [ "${toString ttsPort}:${toString ttsPort}" ];
              networks = [ "kokoro.network" ];
              environments = {
                WYOMING_URI = "tcp://0.0.0.0:${toString ttsPort}";
                WYOMING_LOG_LEVEL = "INFO";
                WYOMING_LANGUAGES = "en";
                TTS_SPEED = "1.2";
                TTS_OPENAI_URL = "http://kokoro:8880/v1";
                TTS_MODELS = "kokoro";
                TTS_STREAMING_MODELS = "kokoro";
                TTS_BACKEND = "KOKORO_FASTAPI";
                TTS_VOICES = "af_bella";
                TTS_STREAMING_MIN_WORDS = "6";
                TTS_STREAMING_MAX_CHARS = "220";
              };
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "kokoro.service";
              Requires = "kokoro.service";
            };
          };
        };
      };
    };
}
