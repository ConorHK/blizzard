{ inputs, ... }:
let
  url = "home.goosebox.org";
in
{
  flake.monitoringChecks.home-assistant = {
    name = "home-assistant";
    url = "https://${url}";
  };

  flake.modules.nixos.home-assistant =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/home-assistant";
      usbDevice = "/dev/ttyUSB0";
    in
    {
      imports = [ inputs.quadlet-nix.nixosModules.quadlet ];

      # Rootful: host network, USB radio and dbus.
      virtualisation.quadlet.containers.homeassistant.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/home-assistant/home-assistant
        image = "ghcr.io/home-assistant/home-assistant:2026.10.3";
        volumes = [
          "${dataDir}:/config"
          "/etc/localtime:/etc/localtime:ro"
          "/run/dbus:/run/dbus:ro"
        ];
        environments.TZ = "Europe/Dublin";
        networks = [ "host" ];
        devices = [ "${usbDevice}:${usbDevice}" ];
        addCapabilities = [
          "NET_RAW"
          "NET_ADMIN"
        ];
      };

      systemd.tmpfiles.rules = [ "d ${dataDir} 0750 root root -" ];

      networking.firewall.allowedTCPPorts = [ 8123 ];

      # Needs trusted_proxies in configuration.yaml.
      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8123";
          proxyWebsockets = true;
        };
      };

      # Home Assistant's own scheduled backups.
      blizzard.backup.jobs.service-data.paths = [ "${dataDir}/backups" ];
    };
}
