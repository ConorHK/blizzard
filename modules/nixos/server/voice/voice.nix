{
  flake.modules.nixos.voice =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/voice";
      whisperPort = 10300;
      ttsPort = 10200;
    in
    {
      home-manager.users.containers.virtualisation.quadlet = {
        networks.kokoro.networkConfig = { };

        containers = {
          wyoming-whisper.containerConfig = {
            # renovate: datasource=docker depName=docker.io/rhasspy/wyoming-whisper
            image = "docker.io/rhasspy/wyoming-whisper:3.8.1@sha256:ba6fcb6056ebe237d15a325381763a80af2fc8fcedaa04f6a714a7375eb20d80";
            publishPorts = [ "${toString whisperPort}:${toString whisperPort}" ];
            volumes = [ "${dataDir}/whisper:/data" ];
            exec = "--model base.en --language en";
            noNewPrivileges = true;
          };

          kokoro.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/remsky/kokoro-fastapi-gpu
            image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.9.0@sha256:9ba150465c6b8f5d6b1c62b54de83eb9aa0a1444aad8a1a9c8948eed60564b76";
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
              image = "ghcr.io/roryeckel/wyoming_openai:latest@sha256:7200ac141cd12594878aca7ce69d7c2159b824a411f25b96ea7431f71d250344";
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
