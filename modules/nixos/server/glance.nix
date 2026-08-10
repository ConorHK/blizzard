_: {
  flake = {
    monitoringChecks.glance = {
      name = "glance";
      url = "https://glance.lep.goosebox.org";
    };

    modules.nixos.glance =
      { pkgs, ... }:
      let
        url = "glance.lep.goosebox.org";
        port = 8092;

        glanceConfig = (pkgs.formats.yaml { }).generate "glance.yml" {
          server.port = 8080;
          # brutalist.report-style layout: one full-width row split into equal
          # columns, each a single source rendered as a plain headline list
          # (no thumbnails), uncollapsed so every story is visible.
          pages = [
            {
              name = "News";
              width = "wide";
              columns = [
                {
                  size = "full";
                  widgets = [
                    {
                      type = "split-column";
                      "max-columns" = 5;
                      widgets = [
                        {
                          type = "hacker-news";
                          limit = 25;
                          "collapse-after" = -1;
                        }
                        {
                          type = "rss";
                          title = "RTÉ News";
                          style = "vertical-list";
                          "single-line-titles" = false;
                          limit = 25;
                          "collapse-after" = -1;
                          feeds = [ { url = "https://www.rte.ie/feeds/rss/?index=/news/&limit=50"; } ];
                        }
                        {
                          type = "lobsters";
                          limit = 15;
                          "collapse-after" = -1;
                        }
                        {
                          type = "rss";
                          title = "Ars Technica";
                          style = "vertical-list";
                          "single-line-titles" = false;
                          limit = 12;
                          "collapse-after" = -1;
                          feeds = [ { url = "https://feeds.arstechnica.com/arstechnica/index"; } ];
                        }
                        {
                          type = "rss";
                          title = "404 Media";
                          style = "vertical-list";
                          "single-line-titles" = false;
                          limit = 12;
                          "collapse-after" = -1;
                          feeds = [ { url = "https://www.404media.co/rss/"; } ];
                        }
                        {
                          type = "rss";
                          title = "BBC World";
                          style = "vertical-list";
                          "single-line-titles" = false;
                          limit = 15;
                          "collapse-after" = -1;
                          feeds = [ { url = "https://feeds.bbci.co.uk/news/world/rss.xml"; } ];
                        }
                        {
                          type = "rss";
                          title = "Financial Times";
                          style = "vertical-list";
                          "single-line-titles" = false;
                          limit = 12;
                          "collapse-after" = -1;
                          feeds = [
                            {
                              url = "https://www.ft.com/rss/home/international";
                              headers."User-Agent" = "Mozilla/5.0 (compatible; Glance RSS)";
                            }
                          ];
                        }
                      ];
                    }
                  ];
                }
              ];
            }
          ];
        };
      in
      {
        networking.firewall.allowedTCPPorts = [ port ];

        home-manager.users.containers.virtualisation.quadlet = {
          networks.glance.networkConfig = { };

          containers.glance.containerConfig = {
            # renovate: datasource=docker depName=docker.io/glanceapp/glance
            image = "docker.io/glanceapp/glance:v0.8.5";
            publishPorts = [ "127.0.0.1:${toString port}:8080" ];
            volumes = [ "${glanceConfig}:/app/config/glance.yml:ro" ];
            environments.TZ = "Europe/Dublin";
            networks = [ "glance.network" ];
            noNewPrivileges = true;
          };
        };

        services.nginx.virtualHosts.${url} = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString port}";
            proxyWebsockets = true;
          };
        };
      };
  };
}
