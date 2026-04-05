_: {
  flake.modules.nixos.paperless-ngx =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8000 ];

      age.secrets.paperless-secrets = {
        rekeyFile = ./secrets/paperless-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.paperless-ngx.networkConfig = { };

        containers = {
          paperless-broker.containerConfig = {
            # renovate: datasource=docker depName=docker.io/library/redis
            image = "docker.io/library/redis:7";
            volumes = [ "/storage/data/paperless-ngx/redis:/data" ];
            networks = [ "paperless-ngx.network" ];
            noNewPrivileges = true;
          };

          paperless-webserver = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/paperless-ngx/paperless-ngx
              image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
              publishPorts = [ "8000:8000" ];
              volumes = [
                "/storage/data/paperless-ngx/data:/usr/src/paperless/data"
                "/storage/data/paperless-ngx/media:/usr/src/paperless/media"
                "/storage/data/paperless-ngx/export:/usr/src/paperless/export"
                "/storage/data/paperless-ngx/consume:/usr/src/paperless/consume"
              ];
              # PAPERLESS_SECRET_KEY loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.paperless-secrets.path ];
              environments = {
                PAPERLESS_REDIS = "redis://paperless-broker:6379";
                PAPERLESS_URL = "https://paperless.goosebox.org";
                PAPERLESS_TIME_ZONE = "Europe/Dublin";
                USERMAP_UID = "1000";
                USERMAP_GID = "1000";
              };
              networks = [ "paperless-ngx.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "paperless-broker.service";
              Requires = "paperless-broker.service";
            };
          };
        };
      };

      services.nginx.virtualHosts."paperless.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8000";
          proxyWebsockets = true;
        };
      };
    };
}
