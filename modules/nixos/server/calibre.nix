_:
let
  calibreDir = "/storage/data/calibre-web-automated";
  shelfmarkDir = "/storage/data/shelfmark";
  ingestDir = "${calibreDir}/injest";
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

    modules.nixos.calibre = _: {
      networking.firewall.allowedTCPPorts = [
        portCalibreWeb
        portShelfmark
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.calibre.networkConfig = { };

        containers = {
          calibre-web.containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/crocodilestick/calibre-web-automated
            image = "ghcr.io/crocodilestick/calibre-web-automated:v4.0.6";
            publishPorts = [ "127.0.0.1:${toString portCalibreWeb}:8083" ];
            volumes = [
              "${calibreDir}/config:/config"
              "${ingestDir}:/cwa-book-ingest"
              "/storage/media/books:/calibre-library"
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
            image = "ghcr.io/calibrain/shelfmark:v1.2.1";
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

      restic.paths = [ "${calibreDir}/config/processed_books/imported" ];

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
