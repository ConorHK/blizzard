_: {
  flake.modules.nixos.glance = _: {
    networking.firewall.allowedTCPPorts = [ 8090 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.glance.networkConfig = { };

      containers.glance.containerConfig = {
        # renovate: datasource=docker depName=glanceapp/glance
        image = "glanceapp/glance:latest";
        publishPorts = [ "8090:8080" ];
        volumes = [ "/storage/data/glance:/app/config" ];
        networks = [ "glance.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."glance.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8090";
        proxyWebsockets = true;
      };
    };
  };
}
