_:
let
  dataDir = "/storage/data/dawarich";
  url = "dawarich.lep.goosebox.org";
  port = 3001;

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
      # Restoring from a restic backup

      # # pull the dump out of the repo (as the containers user, which owns the repo creds)
      # asc restic -r <repo> restore latest --include /storage/data/dawarich/dumps --target /tmp/restore

      # asc systemctl --user stop dawarich-app dawarich-sidekiq
      # gunzip < /tmp/restore/storage/data/dawarich/dumps/dawarich.sql.gz \
      # | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" \
      # | asc podman exec -i dawarich-db psql --username=postgres

      # # re-align the password (dump carries the old one), then start:
      # APP_PW=$(sudo sed -n 's/^DATABASE_PASSWORD=//p' /run/agenix/dawarich-secrets)
      # asc podman exec -i dawarich-db psql -U postgres -c "ALTER ROLE postgres PASSWORD '${APP_PW}';"
      # asc systemctl --user start dawarich-app dawarich-sidekiq

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
            image = "docker.io/redis:7.4-alpine";
            exec = "redis-server";
            volumes = [ "${dataDir}/shared:/data" ];
            networks = [ "dawarich.network" ];
            noNewPrivileges = true;
          };

          dawarich-db.containerConfig = {
            # renovate: datasource=docker depName=docker.io/postgis/postgis
            image = "docker.io/postgis/postgis:17-3.5-alpine";
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
              # renovate: datasource=docker depName=docker.io/freikin/dawarich
              image = "docker.io/freikin/dawarich:1.12.2";
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
              image = "docker.io/freikin/dawarich:1.10.3";
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

      home-manager.users.containers.systemd.user = {
        services.dawarich-db-dump = {
          Unit.Description = "Dump the Dawarich Postgres database";
          Service = {
            Type = "oneshot";
            ExecStart = "${dbDump}/bin/dawarich-db-dump";
          };
        };
        timers.dawarich-db-dump = {
          Unit.Description = "Daily Dawarich Postgres dump";
          # Ahead of the 03:00 restic run so it captures a fresh dump.
          Timer = {
            OnCalendar = "02:45";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

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
