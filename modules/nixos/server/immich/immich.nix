_: {
  flake.modules.nixos.immich =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [ 2283 ];

      age.secrets.immich-secrets = {
        rekeyFile = ./secrets/immich-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.immich.networkConfig = { };

        containers = {
          immich-redis.containerConfig = {
            # renovate: datasource=docker depName=docker.io/redis
            image = "docker.io/redis:6.2-alpine";
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-db.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/immich-app/postgres
            image = "ghcr.io/immich-app/postgres:14-vectorchord0.3.0-pgvectors0.2.0";
            volumes = [ "/storage/data/immich/db:/var/lib/postgresql/data" ];
            # POSTGRES_PASSWORD loaded from agenix-managed env file
            environmentFiles = [ config.age.secrets.immich-secrets.path ];
            environment = {
              POSTGRES_USER = "postgres";
              POSTGRES_DB = "immich";
              POSTGRES_INITDB_ARGS = "--data-checksums";
            };
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-machine-learning.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/immich-app/immich-machine-learning
            image = "ghcr.io/immich-app/immich-machine-learning:release";
            volumes = [ "/storage/data/immich/model-cache:/cache" ];
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-server = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/immich-app/immich-server
              image = "ghcr.io/immich-app/immich-server:release";
              publishPorts = [ "2283:2283" ];
              volumes = [
                "/storage/data/immich/upload:/usr/src/app/upload"
                "/etc/localtime:/etc/localtime:ro"
              ];
              # DB_PASSWORD loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.immich-secrets.path ];
              environment = {
                DB_HOSTNAME = "immich-db";
                DB_USERNAME = "postgres";
                DB_DATABASE_NAME = "immich";
                REDIS_HOSTNAME = "immich-redis";
              };
              networks = [ "immich.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "immich-db.service immich-redis.service";
              Requires = "immich-db.service immich-redis.service";
            };
          };
        };
      };

      services.nginx.virtualHosts."photos.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        # Immich requires large body size for photo/video uploads
        extraConfig = ''
          client_max_body_size 0;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:2283";
          proxyWebsockets = true;
        };
      };
    };
}
