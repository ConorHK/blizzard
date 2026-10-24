{ config, lib, ... }:
let
  upstream = config.flake.tailnetAddresses.sluagh;

  # sluagh's compose apps, served from leprechaun.
  apps = {
    jellyfin = {
      port = 8096;
      health = "/health";
      alias = "tv";
    };
    qbittorrent = {
      port = 8080;
      health = "/";
      alias = "torrent";
    };
    sonarr = {
      port = 8989;
      health = "/ping";
    };
    radarr = {
      port = 7878;
      health = "/ping";
    };
    prowlarr = {
      port = 9696;
      health = "/ping";
    };
    bazarr = {
      port = 6767;
      health = "/";
    };
    cross-seed = {
      port = 2468;
      health = "/api/ping";
      alias = "crossseed";
    };
  };

  domain = name: "${name}.goosebox.org";
in
{
  flake = {
    monitoringChecks = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "sluagh-${name}" {
        name = "sluagh-${name}";
        url = "https://${domain name}${app.health}";
      }
    ) apps;

    modules.nixos.sluagh-proxy = {
      services.nginx.virtualHosts = lib.mapAttrs' (
        name: app:
        lib.nameValuePair (domain name) {
          enableACME = true;
          forceSSL = true;
          # Redirects make API clients drop auth.
          serverAliases = lib.optional (app ? alias) (domain app.alias);
          locations."/" = {
            proxyPass = "http://${upstream}:${toString app.port}";
            proxyWebsockets = true;
            # Stream video without buffering it to disk.
            extraConfig = lib.optionalString (name == "jellyfin") "proxy_buffering off;";
          };
        }
      ) apps;
    };
  };
}
