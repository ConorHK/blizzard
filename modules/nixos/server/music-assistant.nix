_:
let
  url = "music-assistant.goosebox.org";
  port = 8095;
  streamPort = 8097;
in
{
  flake.monitoringChecks.music-assistant = {
    name = "music-assistant";
    url = "https://${url}";
  };

  flake.modules.nixos.music-assistant =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/music-assistant";
    in
    {
      networking.firewall.allowedTCPPorts = [
        port
        streamPort
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        containers.music-assistant-server.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/music-assistant/server
          image = "ghcr.io/music-assistant/server:2.10.4@sha256:37a9a2776e838a754c9f5b38c432567389952304e7cb8f6b44b6cd28043de6de";
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
