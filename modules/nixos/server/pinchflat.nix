_:
let
  url = "pinchflat.goosebox.org";
  port = 8945;
in
{
  flake.monitoringChecks.pinchflat = {
    name = "pinchflat";
    url = "https://${url}/healthcheck";
  };

  flake.modules.nixos.pinchflat =
    { config, ... }:
    let
      inherit (config.blizzard.storage) data media;
      dataDir = "${data}/pinchflat";
    in
    {
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${media}/youtube 0775 containers containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet.containers.pinchflat.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/kieraneglin/pinchflat
        image = "ghcr.io/kieraneglin/pinchflat:v2025.6.6";
        publishPorts = [ "127.0.0.1:${toString port}:8945" ];
        volumes = [
          "${dataDir}:/config"
          "${media}/youtube:/downloads"
        ];
        environments.TZ = "Europe/Dublin";
        noNewPrivileges = true;
      };

      blizzard.backup.jobs.service-data = {
        # Stopped for a consistent SQLite copy.
        paths = [ dataDir ];
        pauseContainers = [ "pinchflat" ];
        exclude = [ "${dataDir}/logs" ];
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
        };
      };
    };
}
