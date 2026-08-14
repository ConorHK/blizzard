_:
let
  dataDir = "/storage/data/actual-budget";
  url = "budget.lep.goosebox.org";
in
{
  flake.monitoringChecks.actual-budget = {
    name = "actual-budget";
    url = "https://${url}";
  };

  flake.modules.nixos.actual-budget = {
    home-manager.users.containers.virtualisation.quadlet = {
      networks.actual-budget.networkConfig = { };

      containers.actual-budget.containerConfig = {
        # renovate: datasource=docker depName=docker.io/actualbudget/actual-server
        image = "docker.io/actualbudget/actual-server:26.8.1";
        publishPorts = [ "127.0.0.1:5006:5006" ];
        volumes = [ "${dataDir}:/data" ];
        networks = [ "actual-budget.network" ];
        noNewPrivileges = true;
      };
    };

    restic.paths = [ dataDir ];
    # Stop the container during the backup: Actual is SQLite-backed, so a live
    # copy of /data can catch a torn write.
    restic.pauseContainers = [ "actual-budget" ];

    services.nginx.virtualHosts.${url} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:5006";
        proxyWebsockets = true;
      };
    };
  };
}
