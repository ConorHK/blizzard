_: {
  flake.modules.nixos.calibre = _: {
    networking.firewall.allowedTCPPorts = [
      8183 # calibre-web-automated
      8085 # calibre-web-automated-book-downloader
      8086 # openbooks
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.calibre.networkConfig = { };

      containers = {
        calibre-web.containerConfig = {
          # renovate: datasource=docker depName=crocodilestick/calibre-web-automated
          image = "crocodilestick/calibre-web-automated:latest";
          publishPorts = [ "8183:8083" ];
          volumes = [
            "/storage/data/calibre/calibre-web/config:/config"
            "/storage/data/calibre/injest:/cwa-book-ingest"
            "/storage/data/media/books:/calibre-library"
          ];
          environment = {
            PUID = "1000";
            PGID = "100";
            TZ = "Europe/Dublin";
          };
          networks = [ "calibre.network" ];
          noNewPrivileges = true;
        };

        calibre-downloader.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/calibrain/calibre-web-automated-book-downloader
          image = "ghcr.io/calibrain/calibre-web-automated-book-downloader:latest";
          publishPorts = [ "8085:8085" ];
          volumes = [ "/storage/data/calibre/injest:/cwa-book-ingest" ];
          environment = {
            FLASK_PORT = "8085";
            FLASK_DEBUG = "false";
            CLOUDFLARE_PROXY_URL = "http://cloudflare-bypass:8000";
            INGEST_DIR = "/cwa-book-ingest";
            BOOK_LANGUAGE = "en";
          };
          networks = [ "calibre.network" ];
          noNewPrivileges = true;
        };

        cloudflare-bypass.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/sarperavci/cloudflarebypassforscraping
          image = "ghcr.io/sarperavci/cloudflarebypassforscraping:latest";
          networks = [ "calibre.network" ];
          noNewPrivileges = true;
        };

        openbooks.containerConfig = {
          # renovate: datasource=docker depName=evanbuss/openbooks
          image = "evanbuss/openbooks:latest";
          publishPorts = [ "8086:80" ];
          volumes = [ "/storage/data/calibre/injest:/books" ];
          environment = {
            BASE_PATH = "/";
          };
          exec = "--name zimder --persist";
          networks = [ "calibre.network" ];
          noNewPrivileges = true;
        };
      };
    };

    services.nginx.virtualHosts = {
      "calibre.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8183";
          proxyWebsockets = true;
        };
      };
      "openbooks.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8086";
          proxyWebsockets = true;
        };
      };
    };
  };
}
