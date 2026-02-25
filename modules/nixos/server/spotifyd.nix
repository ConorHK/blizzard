{
  flake.modules.nixos.spotifyd =
    {
      config,
      lib,
      ...
    }:
    {
      services.pulseaudio.extraConfig = ''
        unload-module module-suspend-on-idle
      '';

      networking = {
        # force use of fallback resolvers
        extraHosts = ''
          0.0.0.0 apresolve.spotify.com
        '';
        firewall = {
          allowedTCPPorts = [
            57621
            59382
          ];
          allowedUDPPorts = [ 5353 ];
        };
      };

      systemd.services.spotifyd = {
        environment = {
          PULSE_SERVER = "unix:///run/pulse/native";
        };
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "spotifyd";
        };
      };

      users.users.spotifyd = {
        isSystemUser = true;
        extraGroups = [ "pipewire" ];
        group = "spotifyd";
      };
      users.groups.spotifyd = { };
      services.spotifyd = {
        enable = true;
        settings = {
          global = {
            device_name = config.networking.hostName;
            device_type = "speaker";
            bitrate = 320;
            initial_volume = 70;
            zeroconf_port = 59382;
            use_mpris = lib.mkDefault false; # true for non-headless
            backend = "pulseaudio";
          };
        };
      };
    };
}
