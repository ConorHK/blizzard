_:
let
  url = "qbittorrent.lep.goosebox.org";
  qbitManageUrl = "qbit-manage.lep.goosebox.org";
  qbittorrentPort = 8080;
  qbitManagePort = 8181;
in
{
  flake = {
    monitoringChecks = {
      qbittorrent = {
        name = "qbittorrent";
        url = "https://${url}";
      };

      qbit-manage = {
        name = "qbit-manage";
        url = "https://${qbitManageUrl}";
      };
    };

    modules.nixos.qbittorrent =
      { config, ... }:
      let
        qbittorrentDir = "${config.blizzard.storage.data}/qbittorrent";
        qbitManageDir = "${config.blizzard.storage.data}/qbit-manage";
        torrentDir = "${config.blizzard.storage.media}/torrents";
      in
      {
        home-manager.users.containers.virtualisation.quadlet = {
          networks.qbittorrent.networkConfig = { };

          containers = {
            qbittorrent.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/hotio/qbittorrent
              image = "ghcr.io/hotio/qbittorrent:release-5.1.4@sha256:a3511925843f3e625ba67a12c36cfaf89762fecc47b6ee064731344d3eef5bdc";
              publishPorts = [ "127.0.0.1:${toString qbittorrentPort}:8080" ];
              volumes = [
                "${qbittorrentDir}:/config"
                "${torrentDir}:/torrents"
              ];
              environments = {
                PUID = "1001";
                PGID = "1001";
                UMASK = "002";
                TZ = "Europe/Dublin";
              };
              networks = [ "qbittorrent.network" ];
              noNewPrivileges = true;
            };

            qbit-manage.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/stuffanthings/qbit_manage
              image = "ghcr.io/stuffanthings/qbit_manage:v4.13.0@sha256:ea04167f627e506b3691304f4c639a52c05584cc9aea4af7ec87d4ed1299e7f5";
              publishPorts = [ "127.0.0.1:${toString qbitManagePort}:8181" ];
              volumes = [
                "${qbitManageDir}:/config:rw"
                "${torrentDir}/downloads:/data:rw"
                "${qbittorrentDir}:/qbittorrent:ro"
              ];
              environments = {
                QBT_WEB_SERVER = "true";
                QBT_PORT = toString qbitManagePort;
              };
              networks = [ "qbittorrent.network" ];
              noNewPrivileges = true;
            };
          };
        };

        services.nginx.virtualHosts."${url}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString qbittorrentPort}";
            proxyWebsockets = true;
          };
        };

        services.nginx.virtualHosts."${qbitManageUrl}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString qbitManagePort}";
            proxyWebsockets = true;
          };
        };
      };
  };
}
