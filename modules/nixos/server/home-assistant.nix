_: {
  flake.modules.nixos.home-assistant = _: {
    networking.firewall.allowedTCPPorts = [ 8123 ];

    # containers user needs bluetooth and dialout for HA's Zigbee/Z-Wave USB adapters
    users.users.containers.extraGroups = [
      "bluetooth"
      "dialout"
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      containers.home-assistant.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/home-assistant/home-assistant
        image = "ghcr.io/home-assistant/home-assistant:stable";
        volumes = [
          "/var/lib/homeassistant/config:/config"
          "/etc/localtime:/etc/localtime:ro"
          "/run/dbus:/run/dbus:ro"
        ];
        environments = {
          TZ = "Europe/Dublin";
        };
        # USB adapter for Zigbee/Z-Wave
        devices = [ "/dev/ttyUSB0" ];
        # Host networking required for mDNS/Chromecast/DLNA discovery
        networks = [ "host" ];
      };
    };
  };
}
