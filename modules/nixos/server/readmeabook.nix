_: {
  flake.modules.nixos.readmeabook = _: {
    networking.firewall.allowedTCPPorts = [
      3030 # readmeabook
      3029 # readmeabook-mom
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.readmeabook.networkConfig = { };

      containers = {
        readmeabook.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/kikootwo/readmeabook
          image = "ghcr.io/kikootwo/readmeabook:latest";
          publishPorts = [ "3030:3030" ];
          volumes = [
            "/storage/data/readmeabook/config:/app/config"
            "/storage/data/readmeabook/cache:/app/cache"
            "/storage/data:/data"
            "/storage/data/media/audiobooks:/media"
            "/storage/data/readmeabook/pgdata:/var/lib/postgresql/data"
            "/storage/data/readmeabook/redis:/var/lib/redis"
          ];
          environments = {
            PUID = "1000";
            PGID = "1000";
            PUBLIC_URL = "https://requestbook.goosebox.com";
          };
          networks = [ "readmeabook.network" ];
          noNewPrivileges = true;
        };

        readmeabook-mom.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/kikootwo/readmeabook
          image = "ghcr.io/kikootwo/readmeabook:latest";
          publishPorts = [ "3029:3030" ];
          volumes = [
            "/storage/data/readmeabook/config-mom:/app/config"
            "/storage/data/readmeabook/cache-mom:/app/cache"
            "/storage/data:/data"
            "/storage/data/media/audiobooks:/media"
            "/storage/data/readmeabook/pgdata-mom:/var/lib/postgresql/data"
            "/storage/data/readmeabook/redis-mom:/var/lib/redis"
          ];
          environments = {
            PUID = "1000";
            PGID = "1000";
            PUBLIC_URL = "https://mom.request.goosebox.com";
          };
          networks = [ "readmeabook.network" ];
          noNewPrivileges = true;
        };
      };
    };

    services.nginx.virtualHosts = {
      "requestbook.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3030";
          proxyWebsockets = true;
        };
      };
      "moms.requestbook.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3029";
          proxyWebsockets = true;
        };
      };
    };
  };
}
