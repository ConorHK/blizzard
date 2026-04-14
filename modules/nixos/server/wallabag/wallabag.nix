_: {
  flake.modules.nixos.wallabag =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 8001 ];

      age.secrets.wallabag-secrets = {
        rekeyFile = ./secrets/wallabag-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.wallabag.networkConfig = { };

        containers = {
          wallabag-db.containerConfig = {
            image = "docker.io/postgres:14";
            volumes = [ "/storage/data/wallabag/data:/var/lib/postgresql/data" ];
            # POSTGRES_PASSWORD loaded from agenix-managed env file
            environmentFiles = [ config.age.secrets.wallabag-secrets.path ];
            environments = {
              POSTGRES_USER = "wallabag";
              POSTGRES_DB = "wallabag";
            };
            networks = [ "wallabag.network" ];
            noNewPrivileges = true;
          };

          wallabag-cache.containerConfig = {
            image = "docker.io/redis:alpine";
            networks = [ "wallabag.network" ];
            noNewPrivileges = true;
          };

          wallabag = {
            containerConfig = {
              # renovate: datasource=docker depName=docker.io/wallabag/wallabag
              image = "docker.io/wallabag/wallabag:latest";
              publishPorts = [ "127.0.0.1:8001:80" ];
              volumes = [ "/storage/data/wallabag/images:/var/www/wallabag/web/assets/images" ];
              # POSTGRES_PASSWORD and SYMFONY__ENV__DATABASE_PASSWORD loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.wallabag-secrets.path ];
              environments = {
                SYMFONY__ENV__DATABASE_DRIVER = "pdo_pgsql";
                SYMFONY__ENV__DATABASE_HOST = "wallabag-db";
                SYMFONY__ENV__DATABASE_PORT = "5432";
                SYMFONY__ENV__DATABASE_NAME = "wallabag";
                SYMFONY__ENV__DATABASE_USER = "wallabag";
                SYMFONY__ENV__REDIS_HOST = "wallabag-cache";
                SYMFONY__ENV__DOMAIN_NAME = "https://wallabag.goosebox.org";
                SYMFONY__ENV__SERVER_NAME = "wallabag";
              };
              networks = [ "wallabag.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "wallabag-db.service wallabag-cache.service";
              Requires = "wallabag-db.service wallabag-cache.service";
            };
          };
        };
      };

      services.nginx.virtualHosts."wallabag.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8001";
          proxyWebsockets = true;
        };
      };
    };
}
