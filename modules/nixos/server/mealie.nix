_: {
  flake.modules.nixos.mealie = _: {
    networking.firewall.allowedTCPPorts = [ 9925 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.mealie.networkConfig = { };

      containers.mealie.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/mealie-recipes/mealie
        image = "ghcr.io/mealie-recipes/mealie:latest";
        publishPorts = [ "9925:9000" ];
        volumes = [ "/storage/data/mealie:/app/data" ];
        environment = {
          ALLOW_SIGNUP = "true";
          PUID = "1000";
          PGID = "1000";
          TZ = "Europe/Dublin";
          MAX_WORKERS = "1";
          WEB_CONCURRENCY = "1";
          BASE_URL = "https://mealie.goosebox.com";
        };
        networks = [ "mealie.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."mealie.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9925";
        proxyWebsockets = true;
      };
    };
  };
}
