_:
let
  portCalibreWeb = 8183;
  portShelfmark = 8084;
  urlCalibreWeb = "calibre.goosebox.org";
  urlShelfmark = "shelfmark.goosebox.org";
in
{
  flake = {
    monitoringChecks = {
      calibre-web = {
        name = "calibre-web";
        url = "https://${urlCalibreWeb}/health";
        conditions = [
          "[STATUS] == 200"
          "[BODY].status == ok"
        ];
      };
      shelfmark = {
        name = "shelfmark";
        url = "https://${urlShelfmark}";
      };
    };

    modules.nixos.calibre =
      { config, ... }:
      let
        calibreDir = "${config.blizzard.storage.data}/calibre-web-automated";
        shelfmarkDir = "${config.blizzard.storage.data}/shelfmark";
        ingestDir = "${calibreDir}/injest";
        booksDir = "${config.blizzard.storage.media}/books";
      in
      {
        home-manager.users.containers.virtualisation.quadlet = {
          networks.calibre.networkConfig = { };

          containers = {
            calibre-web.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/crocodilestick/calibre-web-automated
              image = "ghcr.io/crocodilestick/calibre-web-automated:v4.0.6@sha256:c31a738b6d5ec6982c050063dd3f063b6943eb1051fc81144789f840d9093a8d";
              publishPorts = [ "127.0.0.1:${toString portCalibreWeb}:8083" ];
              volumes = [
                "${calibreDir}/config:/config"
                "${ingestDir}:/cwa-book-ingest"
                "${booksDir}:/calibre-library"
              ];
              environments = {
                PUID = "1000";
                PGID = "1000";
                TZ = "Europe/Dublin";
              };
              networks = [ "calibre.network" ];
              noNewPrivileges = true;
            };

            shelfmark.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/calibrain/shelfmark
              image = "ghcr.io/calibrain/shelfmark:v1.3.15@sha256:9602290324993c801b319d3166b202b96bd9039af2416f0916dae03a5bdca815";
              publishPorts = [ "127.0.0.1:${toString portShelfmark}:${toString portShelfmark}" ];
              volumes = [
                "${shelfmarkDir}:/config"
                "${ingestDir}:/books"
              ];
              environments = {
                PUID = "1000";
                PGID = "1000";
                FLASK_PORT = toString portShelfmark;
                BOOK_LANGUAGE = "en";
              };
              networks = [ "calibre.network" ];
              noNewPrivileges = true;
            };
          };
        };

        restic.paths = [
          calibreDir
          shelfmarkDir
          booksDir
        ];
        restic.pauseContainers = [
          "calibre-web"
          "shelfmark"
        ];

        services.nginx.virtualHosts = {
          "${urlCalibreWeb}" = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString portCalibreWeb}";
              proxyWebsockets = true;
            };
          };
          "${urlShelfmark}" = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString portShelfmark}";
              proxyWebsockets = true;
            };
          };
        };
      };
  };
}
