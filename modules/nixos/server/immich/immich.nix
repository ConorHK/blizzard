_:
let
  dataDir = "/storage/data/immich";
  url = "photos.lep.goosebox.org";
in
{
  flake.monitoringChecks.immich = {
    name = "immich";
    url = "https://${url}";
  };

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
            image = "docker.io/valkey/valkey:9@sha256:3b55fbaa0cd93cf0d9d961f405e4dfcc70efe325e2d84da207a0a8e6d8fde4f9";
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-db.containerConfig = {
            image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
            volumes = [ "${dataDir}/pgdata:/var/lib/postgresql/data" ];
            environmentFiles = [ config.age.secrets.immich-secrets.path ];
            environments = {
              POSTGRES_USER = "admin";
              POSTGRES_DB = "immich";
              POSTGRES_INITDB_ARGS = "--data-checksums";
            };
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-machine-learning.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/immich-app/immich-machine-learning
            image = "ghcr.io/immich-app/immich-machine-learning:v2.7.4";
            volumes = [ "${dataDir}/models:/cache" ];
            networks = [ "immich.network" ];
            noNewPrivileges = true;
          };

          immich-server = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/immich-app/immich-server
              image = "ghcr.io/immich-app/immich-server:v2.7.5";
              publishPorts = [ "127.0.0.1:2283:2283" ];
              volumes = [
                "${dataDir}:/usr/src/app/upload"
                "/etc/localtime:/etc/localtime:ro"
              ];
              # DB_PASSWORD loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.immich-secrets.path ];
              environments.REDIS_HOSTNAME = "immich-redis";
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

      # restic.paths = [
      #   "${dataDir}/backups"
      #   "${dataDir}/library"
      #   "${dataDir}/profile"
      #   "${dataDir}/upload"
      # ];

      services.nginx.virtualHosts.${url} = {
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
