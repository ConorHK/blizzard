_:
let
  dataDir = "/storage/data/music-assistant";
  url = "music-assistant.goosebox.org";
  port = 8095;
  streamPort = 8097;
in
{
  flake.monitoringChecks.music-assistant = {
    name = "music-assistant";
    url = "https://${url}";
  };

  flake.modules.nixos.music-assistant = {
    networking.firewall.allowedTCPPorts = [
      port
      streamPort
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      containers.music-assistant-server.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/music-assistant/server
        image = "ghcr.io/music-assistant/server:2.8.8";
        volumes = [ "${dataDir}:/data" ];
        networks = [ "host" ];
        environments = {
          LOG_LEVEL = "info";
        };
      };
    };

    restic.paths = [ dataDir ];

    services.nginx.virtualHosts.${url} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8095";
        proxyWebsockets = true;
      };
    };
  };
}
