_:
let
  dataDir = "/storage/data/mealie";
  url = "mealie.lep.goosebox.org";
in
{
  flake.monitoringChecks.mealie = {
    name = "mealie";
    url = "https://${url}";
  };

  flake.modules.nixos.mealie = {
    networking.firewall.allowedTCPPorts = [ 9925 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.mealie.networkConfig = { };

      containers.mealie.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/mealie-recipes/mealie
        image = "ghcr.io/mealie-recipes/mealie:v3.15.2";
        publishPorts = [ "127.0.0.1:9925:9000" ];
        volumes = [ "${dataDir}:/app/data" ];
        environments = {
          ALLOW_SIGNUP = "true";
          PUID = "1000";
          PGID = "1000";
          TZ = "Europe/Dublin";
          MAX_WORKERS = "1";
          WEB_CONCURRENCY = "1";
          BASE_URL = "https://${url}";
        };
        networks = [ "mealie.network" ];
        noNewPrivileges = true;
      };
    };

    restic.paths = [ dataDir ];
    restic.pauseContainers = [ "mealie" ];

    services.nginx.virtualHosts.${url} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9925";
        proxyWebsockets = true;
      };
    };
  };
}
