_:
let
  dataDir = "/storage/data/photon";
  url = "photon.lep.goosebox.org";
in
{
  flake.monitoringChecks.photon = {
    name = "photon";
    url = "https://${url}/reverse?lon=-6.2603&lat=53.3498";
  };

  flake.modules.nixos.photon = {
    home-manager.users.containers.virtualisation.quadlet = {
      networks.photon.networkConfig = { };

      containers.photon.containerConfig = {
        # renovate: datasource=docker depName=rtuszik/photon-docker
        image = "rtuszik/photon-docker:2.3.1";
        publishPorts = [ "127.0.0.1:2322:2322" ];
        volumes = [ "${dataDir}:/photon/data" ];
        environments = {
          REGION = "planet";
          IMPORT_MODE = "jsonl";
          REVERSE_ONLY = "TRUE";
          UPDATE_STRATEGY = "DISABLED";
        };
        networks = [ "photon.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts.${url} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:2322";
    };
  };
}
