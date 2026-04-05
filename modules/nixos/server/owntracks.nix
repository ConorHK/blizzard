_: {
  flake.modules.nixos.owntracks = _: {
    networking.firewall.allowedTCPPorts = [
      8083 # otrecorder
      8084 # owntracks-frontend
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.owntracks.networkConfig = { };

      containers = {
        otrecorder.containerConfig = {
          # renovate: datasource=docker depName=owntracks/recorder
          image = "owntracks/recorder:latest";
          publishPorts = [ "8083:8083" ];
          volumes = [
            "/storage/data/owntracks/config:/config"
            "/storage/data/owntracks/store:/store"
          ];
          environments = {
            OTR_PORT = "0";
          };
          networks = [ "owntracks.network" ];
          noNewPrivileges = true;
        };

        owntracks-frontend.containerConfig = {
          # renovate: datasource=docker depName=owntracks/frontend
          image = "owntracks/frontend:latest";
          publishPorts = [ "8084:80" ];
          volumes = [
            "/storage/data/owntracks/frontend/config.js:/usr/share/nginx/html/config/config.js:ro"
          ];
          environments = {
            SERVER_HOST = "otrecorder";
            SERVER_PORT = "8083";
          };
          networks = [ "owntracks.network" ];
          noNewPrivileges = true;
        };
      };
    };

    services.nginx.virtualHosts = {
      "location.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8083";
          proxyWebsockets = true;
        };
      };
      "owntracks.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8084";
          proxyWebsockets = true;
        };
      };
    };
  };
}
