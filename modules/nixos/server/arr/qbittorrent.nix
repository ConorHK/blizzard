_:
let
  url = "qui.lep.goosebox.org";
  quiPort = 7476;
in
{
  flake = {
    monitoringChecks.qui = {
      name = "qui";
      url = "https://${url}";
    };

    modules.nixos.qbittorrent =
      { config, ... }:
      let
        inherit (config.blizzard.storage) data media;
        qbittorrentDir = "${data}/qbittorrent";
        quiDir = "${data}/qui";
      in
      {
        age.secrets.gluetun = {
          rekeyFile = ./secrets/gluetun.age;
          owner = "containers";
        };

        systemd.tmpfiles.rules = [
          "d ${qbittorrentDir} 0750 containers containers -"
          "d ${quiDir} 0750 containers containers -"
          "d ${media}/torrents 0775 containers containers -"
        ];

        home-manager.users.containers.virtualisation.quadlet = {
          networks.arr.networkConfig = { };

          containers = {
            gluetun = {
              containerConfig = {
                # renovate: datasource=docker depName=docker.io/qmcgaw/gluetun
                image = "docker.io/qmcgaw/gluetun:v3.41.3";
                addCapabilities = [ "NET_ADMIN" ];
                devices = [ "/dev/net/tun" ];
                environmentFiles = [ config.age.secrets.gluetun.path ];
                environments = {
                  VPN_SERVICE_PROVIDER = "nordvpn";
                  VPN_TYPE = "wireguard";
                  SERVER_COUNTRIES = "Ireland";
                  # qBittorrent WebUI, for qui and the arrs.
                  FIREWALL_INPUT_PORTS = "8080";
                  TZ = "Europe/Dublin";
                };
                networks = [ "arr.network" ];
              };
              # A new gluetun netns strands qbittorrent; restart it.
              unitConfig.Upholds = "qbittorrent.service";
            };

            qbittorrent = {
              containerConfig = {
                # renovate: datasource=docker depName=ghcr.io/hotio/qbittorrent
                image = "ghcr.io/hotio/qbittorrent:release-5.1.4";
                volumes = [
                  "${qbittorrentDir}:/config"
                  "${media}:/data"
                ];
                environments = {
                  # Container root is the host containers user.
                  PUID = "0";
                  PGID = "0";
                  UMASK = "002";
                  TZ = "Europe/Dublin";
                };
                networks = [ "gluetun.container" ];
                noNewPrivileges = true;
              };
              unitConfig = {
                BindsTo = "gluetun.service";
                After = "gluetun.service";
              };
            };

            qui.containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/autobrr/qui
              image = "ghcr.io/autobrr/qui:v1.31.0";
              publishPorts = [ "127.0.0.1:${toString quiPort}:7476" ];
              volumes = [
                "${quiDir}:/config"
                "${media}:/data"
              ];
              environments = {
                QUI__HOST = "0.0.0.0";
                TZ = "Europe/Dublin";
              };
              user = "0:0";
              networks = [ "arr.network" ];
              noNewPrivileges = true;
            };
          };
        };

        services.nginx.virtualHosts.${url} = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:${toString quiPort}";
            proxyWebsockets = true;
          };
        };
      };
  };
}
