{
  flake.modules.nixos.home-assistant =
    { lib, ... }:
    let
      configPath = "/home/driver/storage/homeassistant/";
      timezone = "Europe/Dublin";
      usbDevice = "/dev/ttyUSB0";
      # TODO: initial load requires mkdir ~/storage/homeassistant and reboot
    in
    {
      virtualisation.oci-containers = {
        backend = lib.mkDefault "podman";

        containers.homeassistant = {
          # renovate: datasource=docker depName=ghcr.io/home-assistant/home-assistant
          image = "ghcr.io/home-assistant/home-assistant:2026.7.2";
          autoStart = true;
          volumes = [
            "${configPath}:/config"
            "/etc/localtime:/etc/localtime:ro"
            "/run/dbus:/run/dbus:ro"
          ];
          environment.TZ = timezone;
          extraOptions = [
            "--network=host"
            "--device=${usbDevice}:${usbDevice}"
            "--cap-add=NET_RAW"
            "--cap-add=NET_ADMIN"
          ];
        };
      };

      networking.firewall.allowedTCPPorts = [ 8123 ];
    };
}
