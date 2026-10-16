_:
let
  url = "paperless.goosebox.org";
in
{
  flake.monitoringChecks.paperless = {
    name = "paperless";
    url = "https://${url}";
  };

  flake.modules.nixos.paperless =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/paperless";
    in
    {
      age.secrets.paperless-secrets = {
        rekeyFile = ./secrets/paperless-secrets.age;
        owner = "containers";
      };

      systemd.tmpfiles.rules = map (d: "d ${dataDir}/${d} 0750 containers containers -") [
        "data"
        "media"
        "export"
        "consume"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.paperless.networkConfig = { };

        containers = {
          paperless-redis.containerConfig = {
            # renovate: datasource=docker depName=docker.io/redis
            image = "docker.io/redis:8.10-alpine";
            networks = [ "paperless.network" ];
            noNewPrivileges = true;
          };

          paperless = {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/paperless-ngx/paperless-ngx
              image = "ghcr.io/paperless-ngx/paperless-ngx:3.3.2";
              publishPorts = [ "127.0.0.1:8010:8000" ];
              volumes = [
                "${dataDir}/data:/usr/src/paperless/data"
                "${dataDir}/media:/usr/src/paperless/media"
                "${dataDir}/export:/usr/src/paperless/export"
                "${dataDir}/consume:/usr/src/paperless/consume"
              ];
              environmentFiles = [ config.age.secrets.paperless-secrets.path ];
              environments = {
                PAPERLESS_URL = "https://${url}";
                PAPERLESS_REDIS = "redis://paperless-redis:6379";
                PAPERLESS_TIME_ZONE = "Europe/Dublin";
                # Container root maps to the host containers user.
                USERMAP_UID = "0";
                USERMAP_GID = "0";
              };
              networks = [ "paperless.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "paperless-redis.service";
              Requires = "paperless-redis.service";
            };
          };
        };
      };

      # Smoke tests skip the documents.
      blizzard.containerSmoke.emptyPaths.paperless = [
        "/usr/src/paperless/consume"
        "/usr/src/paperless/export"
        "/usr/src/paperless/media"
      ];

      restic.paths = [ dataDir ];
      # SQLite: stop to avoid a torn copy.
      restic.pauseContainers = [ "paperless" ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        extraConfig = ''
          client_max_body_size 100M;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:8010";
          proxyWebsockets = true;
        };
      };
    };
}
