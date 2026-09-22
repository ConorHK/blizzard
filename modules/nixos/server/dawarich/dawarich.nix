_:
let
  url = "dawarich.lep.goosebox.org";
  port = 3001;

  # renovate: datasource=docker depName=docker.io/freikin/dawarich
  dawarichImage = "docker.io/freikin/dawarich:1.14.5@sha256:11826c67e4b1cfc1049033b5b6ad05f5134bcbfb7807045bd39d3376cbc79d89";

  appEnv = {
    RAILS_ENV = "development";
    REDIS_URL = "redis://dawarich-redis:6379";
    DATABASE_HOST = "dawarich-db";
    DATABASE_USERNAME = "postgres";
    DATABASE_NAME = "dawarich_development";
    APPLICATION_HOSTS = "localhost,${url},location.goosebox.org,dawarich.goosebox.org,locationapi.goosebox.org";
    APPLICATION_PROTOCOL = "https";
    TIME_ZONE = "Europe/Dublin";
    SELF_HOSTED = "true";
    STORE_GEODATA = "true";
    PHOTON_API_HOST = "photon.dawarich.app";
    PHOTON_API_USE_HTTPS = "true";
    PROMETHEUS_EXPORTER_ENABLED = "false";
  };
in
{
  flake.monitoringChecks.dawarich = {
    name = "dawarich";
    url = "https://${url}/api/v1/health";
  };

  flake.modules.nixos.dawarich =
    { config, pkgs, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/dawarich";

      # Restore steps: docs/audit-deployment.md.
      dbDump = pkgs.writeShellApplication {
        name = "dawarich-db-dump";
        runtimeInputs = [
          pkgs.podman
          pkgs.gzip
          pkgs.coreutils
        ];
        text = ''
          dir=${dataDir}/dumps
          mkdir -p "$dir"
          podman exec dawarich-db pg_dumpall --clean --if-exists --username=postgres \
            | gzip >"$dir/dawarich.sql.gz.tmp"
          mv -f "$dir/dawarich.sql.gz.tmp" "$dir/dawarich.sql.gz"
        '';
      };
    in
    {
      age.secrets.dawarich-secrets = {
        rekeyFile = ./secrets/dawarich-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.dawarich.networkConfig = { };

        containers = {
          dawarich-redis.containerConfig = {
            # renovate: datasource=docker depName=docker.io/redis
            image = "docker.io/redis:7.4-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499";
            exec = "redis-server";
            volumes = [ "${dataDir}/shared:/data" ];
            networks = [ "dawarich.network" ];
            noNewPrivileges = true;
          };

          dawarich-db.containerConfig = {
            # renovate: datasource=docker depName=docker.io/postgis/postgis
            image = "docker.io/postgis/postgis:17-3.5-alpine@sha256:894f570c0cf0664ed5576a8fd5d5bfb8fb1b19d592885b686c3a88c8bd90c41f";
            shmSize = "1g";
            volumes = [
              "${dataDir}/db_data_pg_17:/var/lib/postgresql/data"
              "${dataDir}/shared:/var/shared"
            ];
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
              image = dawarichImage;
              entrypoint = "web-entrypoint.sh";
              exec = [
                "bin/rails"
                "server"
                "-p"
                "3000"
                "-b"
                "::"
              ];
              publishPorts = [ "127.0.0.1:${toString port}:3000" ];
              volumes = [
                "${dataDir}/public:/var/app/public"
                "${dataDir}/watched:/var/app/tmp/imports/watched"
                "${dataDir}/storage:/var/app/storage"
              ];
              environmentFiles = [ config.age.secrets.dawarich-secrets.path ];
              environments = appEnv // {
                MIN_MINUTES_SPENT_IN_CITY = "60";
              };
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
              image = dawarichImage;
              entrypoint = "sidekiq-entrypoint.sh";
              exec = "sidekiq";
              volumes = [
                "${dataDir}/public:/var/app/public"
                "${dataDir}/watched:/var/app/tmp/imports/watched"
                "${dataDir}/storage:/var/app/storage"
              ];
              environmentFiles = [ config.age.secrets.dawarich-secrets.path ];
              environments = appEnv // {
                BACKGROUND_PROCESSING_CONCURRENCY = "10";
              };
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

      systemd.services.dawarich-db-dump = {
        description = "Dump Dawarich database";
        after = [ "home-manager-containers.service" ];
        requires = [ "home-manager-containers.service" ];
        unitConfig.OnFailure = "alert-failure@dawarich-db-dump.service";
        environment.XDG_RUNTIME_DIR = "/run/user/${toString config.users.users.containers.uid}";
        serviceConfig = {
          Type = "oneshot";
          User = "containers";
          UMask = "0077";
          ExecStart = "${dbDump}/bin/dawarich-db-dump";
        };
      };
      restic.prepareUnits = [ "dawarich-db-dump.service" ];

      # Back up the logical dump (not the live datadir) plus the app's file
      # volumes. No pauseContainers: the dump is self-consistent, so the stack
      # keeps running during the backup.
      restic.paths = [
        "${dataDir}/dumps"
        "${dataDir}/public"
        "${dataDir}/storage"
        "${dataDir}/watched"
      ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          client_max_body_size 0;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
        };
      };
    };
}
