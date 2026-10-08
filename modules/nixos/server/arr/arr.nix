{ lib, ... }:
let
  # Web apps behind nginx at <name>.lep.goosebox.org.
  apps = {
    sonarr = {
      # renovate: datasource=docker depName=ghcr.io/hotio/sonarr
      image = "ghcr.io/hotio/sonarr:release-4.0.20.3014";
      port = 8989;
      health = "/ping";
      media = true;
      hotio = true;
    };
    radarr = {
      # renovate: datasource=docker depName=ghcr.io/hotio/radarr
      image = "ghcr.io/hotio/radarr:release-6.4.4.10685";
      port = 7878;
      health = "/ping";
      media = true;
      hotio = true;
    };
    prowlarr = {
      # renovate: datasource=docker depName=ghcr.io/hotio/prowlarr
      image = "ghcr.io/hotio/prowlarr:release-2.6.5.5623";
      port = 9696;
      health = "/ping";
      media = false;
      hotio = true;
    };
    bazarr = {
      # renovate: datasource=docker depName=ghcr.io/hotio/bazarr
      image = "ghcr.io/hotio/bazarr:release-1.6.2";
      port = 6767;
      health = "/";
      media = true;
      hotio = true;
    };
    autobrr = {
      # renovate: datasource=docker depName=ghcr.io/autobrr/autobrr
      image = "ghcr.io/autobrr/autobrr:v1.88.0";
      port = 7474;
      health = "/api/healthz/liveness";
      media = false;
      hotio = false;
      environments.AUTOBRR__HOST = "0.0.0.0";
    };
  };

  host = name: "${name}.lep.goosebox.org";
in
{
  flake = {
    monitoringChecks = lib.mapAttrs (name: app: {
      inherit name;
      url = "https://${host name}${app.health}";
    }) apps;

    modules.nixos.arr =
      { config, pkgs, ... }:
      let
        inherit (config.blizzard.storage) data media;
        apiKeys = config.age.secrets.arr-api-keys.path;
        tz = "Europe/Dublin";

        # Guide profiles; default CF groups sync with them.
        recyclarrConfig = pkgs.writeText "recyclarr.yml" ''
          sonarr:
            sonarr:
              base_url: http://sonarr:8989
              api_key: !env_var SONARR__AUTH__APIKEY
              quality_definition:
                type: series
              quality_profiles:
                - trash_id: 72dae194fc92bf828f32cde7744e51a1 # WEB-1080p
                  reset_unmatched_scores:
                    enabled: true

          radarr:
            radarr:
              base_url: http://radarr:7878
              api_key: !env_var RADARR__AUTH__APIKEY
              quality_definition:
                type: movie
              quality_profiles:
                - trash_id: d1d67249d3890e49bc12e275d989a7e9 # HD Bluray + WEB
                  reset_unmatched_scores:
                    enabled: true
        '';

        hotioEnv = {
          # Container root is the host containers user.
          PUID = "0";
          PGID = "0";
          UMASK = "002";
          TZ = tz;
        };

        appContainer = name: app: {
          inherit (app) image;
          publishPorts = [ "127.0.0.1:${toString app.port}:${toString app.port}" ];
          volumes = [ "${data}/${name}:/config" ] ++ lib.optional app.media "${media}:/data";
          environments = (if app.hotio then hotioEnv else { TZ = tz; }) // app.environments or { };
          # Pins each arr's API key for recyclarr and unpackerr.
          environmentFiles = lib.optional app.hotio apiKeys;
          user = if app.hotio then null else "0:0";
          networks = [ "arr.network" ];
          noNewPrivileges = true;
        };
      in
      {
        age.secrets.arr-api-keys = {
          rekeyFile = ./secrets/arr-api-keys.age;
          owner = "containers";
        };

        systemd.tmpfiles.rules =
          map (name: "d ${data}/${name} 0750 containers containers -") (lib.attrNames apps ++ [ "recyclarr" ])
          ++ [
            "d ${media}/tv 0775 containers containers -"
            "d ${media}/movies 0775 containers containers -"
          ];

        home-manager.users.containers.virtualisation.quadlet = {
          networks.arr.networkConfig = { };

          containers = lib.mapAttrs (name: app: { containerConfig = appContainer name app; }) apps // {
            recyclarr.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/recyclarr/recyclarr
              image = "ghcr.io/recyclarr/recyclarr:8.7.3";
              volumes = [
                "${data}/recyclarr:/config"
                "${recyclarrConfig}:/config/recyclarr.yml:ro"
              ];
              environmentFiles = [ apiKeys ];
              environments.TZ = tz;
              user = "0:0";
              networks = [ "arr.network" ];
              noNewPrivileges = true;
            };

            unpackerr.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/unpackerr/unpackerr
              image = "ghcr.io/unpackerr/unpackerr:v0.16.1";
              volumes = [ "${media}/torrents:/data/torrents" ];
              environmentFiles = [ apiKeys ];
              environments = {
                TZ = tz;
                UN_SONARR_0_URL = "http://sonarr:8989";
                UN_SONARR_0_PATHS_0 = "/data/torrents";
                UN_RADARR_0_URL = "http://radarr:7878";
                UN_RADARR_0_PATHS_0 = "/data/torrents";
              };
              user = "0:0";
              networks = [ "arr.network" ];
              noNewPrivileges = true;
            };
          };
        };

        services.nginx.virtualHosts = lib.mapAttrs' (
          name: app:
          lib.nameValuePair (host name) {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString app.port}";
              proxyWebsockets = true;
            };
          }
        ) apps;
      };
  };
}
