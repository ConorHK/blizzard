_: {
  flake.modules.nixos.dawarich =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 3001 ];

      age.secrets.dawarich-secrets = {
        rekeyFile = ./secrets/dawarich-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.dawarich.networkConfig = { };

        containers = {
          dawarich-redis.containerConfig = {
            # renovate: datasource=docker depName=redis
            image = "redis:8.6-alpine";
            exec = "redis-server";
            volumes = [ "/storage/data/dawarich/shared:/data" ];
            networks = [ "dawarich.network" ];
            noNewPrivileges = true;
          };

          dawarich-db.containerConfig = {
            # renovate: datasource=docker depName=postgis/postgis
            image = "postgis/postgis:17-3.5-alpine";
            volumes = [
              "/storage/data/dawarich/db_data:/var/lib/postgresql/data"
              "/storage/data/dawarich/shared:/var/shared"
            ];
            # POSTGRES_PASSWORD loaded from agenix-managed env file
            environmentFiles = [ config.age.secrets.dawarich-secrets.path ];
            environments = {
              POSTGRES_USER = "postgres";
              POSTGRES_DB = "dawarich_development";
            };
            networks = [ "dawarich.network" ];
            noNewPrivileges = true;
          };

          dawarich-app = {
            containerConfig = {
              # renovate: datasource=docker depName=freikin/dawarich
              image = "freikin/dawarich:latest";
              publishPorts = [ "3001:3000" ];
              volumes = [
                "/storage/data/dawarich/public:/var/app/public"
                "/storage/data/dawarich/watched:/var/app/tmp/imports/watched"
                "/storage/data/dawarich/storage:/var/app/storage"
              ];
              # DATABASE_PASSWORD loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.dawarich-secrets.path ];
              environments = {
                RAILS_ENV = "development";
                REDIS_URL = "redis://dawarich-redis:6379";
                DATABASE_HOST = "dawarich-db";
                DATABASE_USERNAME = "postgres";
                DATABASE_NAME = "dawarich_development";
                MIN_MINUTES_SPENT_IN_CITY = "60";
                APPLICATION_HOSTS = "localhost,location.goosebox.org,dawarich.goosebox.org,locationapi.goosebox.org";
                TIME_ZONE = "Europe/Dublin";
                APPLICATION_PROTOCOL = "http";
                PROMETHEUS_EXPORTER_ENABLED = "false";
                SELF_HOSTED = "true";
                STORE_GEODATA = "true";
              };
              entrypoint = "web-entrypoint.sh";
              exec = "bin/rails server -p 3000 -b ::";
              networks = [ "dawarich.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "dawarich-db.service dawarich-redis.service";
              Requires = "dawarich-db.service dawarich-redis.service";
            };
          };

          dawarich-sidekiq = {
            containerConfig = {
              # renovate: datasource=docker depName=freikin/dawarich
              image = "freikin/dawarich:latest";
              volumes = [
                "/storage/data/dawarich/public:/var/app/public"
                "/storage/data/dawarich/watched:/var/app/tmp/imports/watched"
                "/storage/data/dawarich/storage:/var/app/storage"
              ];
              # DATABASE_PASSWORD loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.dawarich-secrets.path ];
              environments = {
                RAILS_ENV = "development";
                REDIS_URL = "redis://dawarich-redis:6379";
                DATABASE_HOST = "dawarich-db";
                DATABASE_USERNAME = "postgres";
                DATABASE_NAME = "dawarich_development";
                APPLICATION_HOSTS = "localhost,location.goosebox.org,dawarich.goosebox.org,locationapi.goosebox.org";
                BACKGROUND_PROCESSING_CONCURRENCY = "10";
                APPLICATION_PROTOCOL = "http";
                PROMETHEUS_EXPORTER_ENABLED = "false";
                SELF_HOSTED = "true";
                STORE_GEODATA = "true";
              };
              entrypoint = "sidekiq-entrypoint.sh";
              exec = "sidekiq";
              networks = [ "dawarich.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "dawarich-db.service dawarich-redis.service dawarich-app.service";
              Requires = "dawarich-db.service dawarich-redis.service dawarich-app.service";
            };
          };
        };
      };

      services.nginx.virtualHosts."dawarich.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
        };
      };
    };
}
