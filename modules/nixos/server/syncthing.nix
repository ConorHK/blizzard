_: {
  flake.modules.nixos.syncthing-server = _: {
    networking.firewall = {
      allowedTCPPorts = [
        8384 # Web UI
        22000 # TCP file transfers
      ];
      allowedUDPPorts = [
        22000 # QUIC file transfers
        21027 # Local discovery broadcasts
      ];
    };

    home-manager.users.containers.virtualisation.quadlet = {
      networks.syncthing.networkConfig = { };

      containers.syncthing.containerConfig = {
        # renovate: datasource=docker depName=syncthing/syncthing
        image = "syncthing/syncthing:latest";
        publishPorts = [
          "8384:8384"
          "22000:22000/tcp"
          "22000:22000/udp"
          "21027:21027/udp"
        ];
        volumes = [ "/storage/data/syncthing:/var/syncthing" ];
        environment = {
          PUID = "1000";
          PGID = "1000";
        };
        networks = [ "syncthing.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."syncthing.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8384";
        proxyWebsockets = true;
      };
    };
  };
}
