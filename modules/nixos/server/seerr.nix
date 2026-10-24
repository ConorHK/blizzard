_:
let
  url = "requests.goosebox.org";
  port = 5055;
in
{
  flake.monitoringChecks.seerr = {
    name = "seerr";
    url = "https://${url}/api/v1/status";
  };

  flake.modules.nixos.seerr =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/seerr";
    in
    {
      systemd.tmpfiles.rules = [ "d ${dataDir} 0750 containers containers -" ];

      # Media servers live on sluagh, reached over the tailnet.
      home-manager.users.containers.virtualisation.quadlet.containers.seerr.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/seerr-team/seerr
        image = "ghcr.io/seerr-team/seerr:v3.5.1";
        publishPorts = [ "127.0.0.1:${toString port}:5055" ];
        volumes = [ "${dataDir}:/app/config" ];
        # Image runs as node; map 1000 to containers.
        userns = "keep-id:uid=1000,gid=1000";
        runInit = true;
        environments.TZ = "Europe/Dublin";
        noNewPrivileges = true;
      };

      blizzard.backup.jobs.service-data = {
        # Stopped for a consistent SQLite copy.
        paths = [ dataDir ];
        pauseContainers = [ "seerr" ];
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
