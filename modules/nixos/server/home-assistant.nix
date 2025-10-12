{
  flake.modules.nixos.home-assistant =
    { config, lib, ... }:
    let
      homeAssistantVersion = "stable";
      configPath = "/home/driver/storage/homeassistant/";
      timezone = "Europe/Dublin";
      usbDevice = "/dev/ttyUSB0";
      # TODO: initial load requires mkdir ~/storage/homeassistant and reboot
    in
    {
      virtualisation.oci-containers = {
        backend = lib.mkDefault "podman";

        containers.homeassistant = {
          image = "ghcr.io/home-assistant/home-assistant:${homeAssistantVersion}";
          autoStart = true;
          volumes = [
            "${configPath}:/config"
            "/etc/localtime:/etc/localtime:ro"
          ];
          environment.TZ = timezone;
          extraOptions = [
            "--network=host"
            "--device=${usbDevice}:${usbDevice}"
          ];
        };
      };

      networking.firewall.allowedTCPPorts = [ 8123 ];
    };
}
