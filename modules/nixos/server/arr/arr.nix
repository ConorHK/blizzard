_: {
  flake.modules.nixos.arr =
    { config, ... }:
    {
      networking.firewall.allowedTCPPorts = [
        8989 # sonarr
        7878 # radarr
        6767 # bazarr
        9696 # prowlarr
        5055 # jellyseerr
        2468 # cross-seed
        3000 # jellystat
      ];

      age.secrets.arr-secrets = {
        rekeyFile = ./secrets/arr-secrets.age;
        owner = "containers";
      };

      home-manager.users.containers.virtualisation.quadlet = {
        networks.arr.networkConfig = { };

        containers = {
          sonarr.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/hotio/sonarr
            image = "ghcr.io/hotio/sonarr:latest";
            publishPorts = [ "8989:8989" ];
            volumes = [
              "/storage/data/sonarr:/config"
              "/storage/media/torrents/data:/data/torrents"
              "/storage/media:/data/media"
            ];
            environments = {
              PUID = "1000";
              PGID = "1000";
              UMASK = "002";
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          radarr.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/hotio/radarr
            image = "ghcr.io/hotio/radarr:latest";
            publishPorts = [ "7878:7878" ];
            volumes = [
              "/storage/data/radarr/config:/config"
              "/storage/media/torrents/data:/data/torrents"
              "/storage/media:/data/media"
            ];
            environments = {
              PUID = "1000";
              PGID = "1000";
              UMASK = "002";
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          bazarr.containerConfig = {
            # renovate: datasource=docker depName=lscr.io/linuxserver/bazarr
            image = "lscr.io/linuxserver/bazarr:latest";
            publishPorts = [ "6767:6767" ];
            volumes = [
              "/storage/data/bazarr:/config"
              "/storage/media:/data/media"
            ];
            environments = {
              PUID = "1000";
              PGID = "1000";
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          prowlarr.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/hotio/prowlarr
            image = "ghcr.io/hotio/prowlarr:latest";
            publishPorts = [ "9696:9696" ];
            volumes = [ "/storage/data/prowlarr:/config" ];
            environments = {
              PUID = "1000";
              PGID = "1000";
              UMASK = "002";
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          jellyseerr.containerConfig = {
            # renovate: datasource=docker depName=fallenbagel/jellyseerr
            image = "fallenbagel/jellyseerr:latest";
            publishPorts = [ "5055:5055" ];
            volumes = [ "/storage/data/jellyseerr/config:/app/config" ];
            environments = {
              LOG_LEVEL = "debug";
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          cross-seed = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/cross-seed/cross-seed
              image = "ghcr.io/cross-seed/cross-seed:6";
              publishPorts = [ "2468:2468" ];
              volumes = [
                "/storage/data/cross-seed/config:/config"
                "/storage/data/qbittorrent/data/BT_backup:/torrents:ro"
                "/storage/data/cross-seed/cross-seeds:/cross-seeds"
                "/storage/media/torrents/data:/data/torrents"
                "/storage/data/cross-seed/output:/output"
              ];
              networks = [ "arr.network" ];
              noNewPrivileges = true;
              user = "1000:1000";
              exec = "daemon";
            };
          };

          recyclarr.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/recyclarr/recyclarr
            image = "ghcr.io/recyclarr/recyclarr:latest";
            volumes = [ "/storage/data/recyclarr:/config" ];
            environments = {
              TZ = "Europe/Dublin";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
            user = "1000:1000";
          };

          unpackerr.containerConfig = {
            # renovate: datasource=docker depName=golift/unpackerr
            image = "golift/unpackerr:latest";
            volumes = [ "/storage/media/torrents/data:/data/torrents" ];
            # API keys and secrets loaded from agenix-managed env file
            environmentFiles = [ config.age.secrets.arr-secrets.path ];
            environments = {
              TZ = "Europe/Dublin";
              UN_DEBUG = "false";
              UN_INTERVAL = "2m";
              UN_START_DELAY = "1m";
              UN_RETRY_DELAY = "5m";
              UN_MAX_RETRIES = "3";
              UN_PARALLEL = "1";
              UN_FILE_MODE = "0644";
              UN_DIR_MODE = "0755";
              # Uses container DNS within arr network
              UN_SONARR_0_URL = "http://sonarr:8989";
              UN_SONARR_0_PATHS_0 = "/downloads";
              UN_SONARR_0_PROTOCOLS = "torrent";
              UN_SONARR_0_TIMEOUT = "10s";
              UN_SONARR_0_DELETE_ORIG = "false";
              UN_SONARR_0_DELETE_DELAY = "5m";
              UN_RADARR_0_URL = "http://radarr:7878";
              UN_RADARR_0_PATHS_0 = "/downloads";
              UN_RADARR_0_PROTOCOLS = "torrent";
              UN_RADARR_0_TIMEOUT = "10s";
              UN_RADARR_0_DELETE_ORIG = "false";
              UN_RADARR_0_DELETE_DELAY = "5m";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
            user = "1000:1000";
          };

          jellystat-db.containerConfig = {
            # renovate: datasource=docker depName=postgres
            image = "postgres:18.3";
            volumes = [ "/storage/data/jellystat/db:/var/lib/postgresql/data" ];
            # POSTGRES_PASSWORD loaded from agenix-managed env file
            environmentFiles = [ config.age.secrets.arr-secrets.path ];
            environments = {
              POSTGRES_DB = "jfstat";
              POSTGRES_USER = "postgres";
            };
            networks = [ "arr.network" ];
            noNewPrivileges = true;
          };

          jellystat = {
            containerConfig = {
              # renovate: datasource=docker depName=cyfershepard/jellystat
              image = "cyfershepard/jellystat:latest";
              publishPorts = [ "3000:3000" ];
              volumes = [ "/storage/data/jellystat/backup:/app/backend/backup-data" ];
              # POSTGRES_PASSWORD and JWT_SECRET loaded from agenix-managed env file
              environmentFiles = [ config.age.secrets.arr-secrets.path ];
              environments = {
                POSTGRES_USER = "postgres";
                POSTGRES_IP = "jellystat-db";
                POSTGRES_PORT = "5432";
              };
              networks = [ "arr.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "jellystat-db.service";
              Requires = "jellystat-db.service";
            };
          };
        };
      };

      # Join qbittorrent containers to arr network so sonarr/radarr/cross-seed can reach them
      home-manager.users.containers.virtualisation.quadlet.containers.qbittorrent.containerConfig.networks =
        [ "arr.network" ];

      services.nginx.virtualHosts."jellystat.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:3000";
          proxyWebsockets = true;
        };
      };
    };
}
