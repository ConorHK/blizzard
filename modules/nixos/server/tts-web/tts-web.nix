{
  flake.modules.nixos.tts-web =
    { pkgs, ... }:
    let
      tts-web-script = pkgs.writeScriptBin "tts-web" ''
        #!${pkgs.bash}/bin/bash
        export PYTHONPATH=${pkgs.python3.withPackages (ps: with ps; [ flask ])}/${pkgs.python3.sitePackages}
        exec ${pkgs.python3}/bin/python3 ${./tts-web.py} \
          --port ${toString 8612} \
          --espeak-path ${pkgs.espeak-ng}/bin/espeak-ng \
          --aplay-path ${pkgs.alsa-utils}/bin/aplay
      '';

    in
    {
      networking.firewall.allowedTCPPorts = [ 8612 ];

      users.users.tts-web = {
        isSystemUser = true;
        group = "audio";
        extraGroups = [
          "audio"
          "pipewire"
        ];
      };

      systemd.services.tts-web = {
        description = "TTS Web Service";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network.target"
          "sound.target"
        ];

        serviceConfig = {
          ExecStart = "${tts-web-script}/bin/tts-web";
          User = "tts-web";
          Group = "audio";
          Restart = "always";
          RestartSec = 5;
        };

        environment = {
          PYTHONPATH = "${pkgs.python3.withPackages (ps: with ps; [ flask ])}/${pkgs.python3.sitePackages}";
        };
      };

      environment.systemPackages = with pkgs; [
        espeak-ng
        alsa-utils
        (python3.withPackages (ps: with ps; [ flask ]))
      ];

    };
}
