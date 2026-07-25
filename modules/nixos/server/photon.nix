_:
let
  dataDir = "/storage/data/photon";
  url = "photon.lep.goosebox.org";
in
{
  flake.monitoringChecks.photon = {
    name = "photon";
    # Photon serves no route at "/"; hit the reverse endpoint (Dublin) so the
    # check only passes once the index has finished importing and is answering.
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
        # Full-planet, reverse-geocoding-only index (~60% smaller than a full
        # forward+reverse build). Downloads on first boot when the data dir is
        # empty; updates disabled — historical geocoding needs no fresh OSM data.
        environments = {
          REGION = "planet";
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
