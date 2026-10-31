_:
let
  url = "qui.lep.goosebox.org";
  quiPort = 7476;
  slskdUrl = "slskd.goosebox.org";
  slskdPort = 5030;
  # AirVPN forwarded port.
  slskdListenPort = 14948;
in
{
  flake = {
    monitoringChecks = {
      qui = {
        name = "qui";
        url = "https://${url}";
      };
      slskd = {
        name = "slskd";
        url = "https://${slskdUrl}/health";
      };
    };

    modules.nixos.qbittorrent =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        inherit (config.blizzard.storage) data media;
        qbittorrentDir = "${data}/qbittorrent";
        quiDir = "${data}/qui";
        slskdDir = "${data}/slskd";
        mamDir = "${data}/mam";
        # slskd refuses to start without them.
        slskdDirs = {
          SLSKD_DOWNLOADS_DIR = "/data/slskd/downloads";
          SLSKD_INCOMPLETE_DIR = "/data/slskd/incomplete";
        };
      in
      {
        # Smoke runs blank the media volume.
        blizzard.containerSmoke.createPaths.slskd = lib.attrValues slskdDirs;

        age.secrets = {
          gluetun = {
            rekeyFile = ./secrets/gluetun.age;
            owner = "containers";
          };
          slskd = {
            rekeyFile = ./secrets/slskd.age;
            owner = "containers";
          };
        };

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
                # slskd web UI, for nginx and lidarr.
                publishPorts = [ "127.0.0.1:${toString slskdPort}:${toString slskdPort}" ];
                environments = {
                  VPN_SERVICE_PROVIDER = "airvpn";
                  VPN_TYPE = "wireguard";
                  SERVER_COUNTRIES = "United Kingdom";
                  # qBittorrent and slskd web UIs.
                  FIREWALL_INPUT_PORTS = "8080,${toString slskdPort}";
                  # AirVPN forwarded ports for qBittorrent and slskd.
                  FIREWALL_VPN_INPUT_PORTS = "38483,${toString slskdListenPort}";
                  TZ = "Europe/Dublin";
                };
                networks = [ "arr.network" ];
              };
              # A new gluetun netns strands its clients; restart them.
              unitConfig.Upholds = "qbittorrent.service slskd.service mam-updater.service";
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

            slskd = {
              containerConfig = {
                # renovate: datasource=docker depName=docker.io/slskd/slskd
                image = "docker.io/slskd/slskd:0.26.2";
                volumes = [
                  "${slskdDir}:/app"
                  "${media}:/data"
                ];
                # Soulseek and web UI credentials, API key.
                environmentFiles = [ config.age.secrets.slskd.path ];
                environments = slskdDirs // {
                  SLSKD_SLSK_LISTEN_PORT = toString slskdListenPort;
                  SLSKD_SHARED_DIR = "/data/music";
                  SLSKD_NO_HTTPS = "true";
                  SLSKD_UMASK = "0002";
                  TZ = "Europe/Dublin";
                };
                user = "0:0";
                networks = [ "gluetun.container" ];
                noNewPrivileges = true;
              };
              unitConfig = {
                BindsTo = "gluetun.service";
                After = "gluetun.service";
              };
            };

            # MAM must see qbittorrent's exit IP.
            mam-updater = {
              containerConfig = {
                # renovate: datasource=docker depName=docker.io/alpine/curl
                image = "docker.io/alpine/curl:8.23.0";
                entrypoint = "/bin/sh";
                exec = "/update.sh";
                volumes = [
                  "${./mam-update.sh}:/update.sh:ro"
                  "${mamDir}:/mam"
                ];
                user = "0:0";
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
              image = "ghcr.io/autobrr/qui:v1.33.1";
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

        systemd = {
          tmpfiles.rules = [
            "d ${qbittorrentDir} 0750 containers containers -"
            "d ${quiDir} 0750 containers containers -"
            "d ${slskdDir} 0750 containers containers -"
            "d ${mamDir} 0700 containers containers -"
            "d ${media}/slskd 0775 containers containers -"
            "d ${media}/slskd/downloads 0775 containers containers -"
            "d ${media}/slskd/incomplete 0775 containers containers -"
            "d ${media}/torrents 0775 containers containers -"
            "d ${media}/torrents/radarr 0775 containers containers -"
            "d ${media}/torrents/sonarr 0775 containers containers -"
            "d ${media}/cross-seed 0775 containers containers -"
          ];

          # Catches failed, stuck or stopped updaters.
          services.mam-watch = {
            description = "Alert when the MAM IP goes stale";
            unitConfig.OnFailure = "alert-failure@mam-watch.service";
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "mam-watch";
            };
            script = ''
              set -uo pipefail
              stamp=${mamDir}/state
              alerted=/var/lib/mam-watch/alerted
              send=${lib.getExe config.blizzard.alerts.send}
              now=$(${pkgs.coreutils}/bin/date +%s)
              seen=$(${pkgs.coreutils}/bin/stat -c %Y "$stamp" 2>/dev/null || echo 0)
              # Updater refreshes every 3h.
              if (( now - seen < 4 * 3600 )); then
                if [ -e "$alerted" ]; then
                  rm "$alerted"
                  $send "MAM IP ok" "MAM accepts the VPN IP again." 3 "+1"
                fi
                exit 0
              fi
              [ -e "$alerted" ] && exit 0
              reason=$(${pkgs.coreutils}/bin/cat ${mamDir}/error 2>/dev/null || echo "updater not running")
              $send "MAM IP stale" "MAM torrents may fail: $reason. See podman logs mam-updater." 4 warning
              touch "$alerted"
            '';
          };

          timers.mam-watch = {
            description = "Check the MAM IP every 15 minutes";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "15min";
              OnUnitActiveSec = "15min";
            };
          };
        };

        services.nginx.virtualHosts = {
          ${url} = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString quiPort}";
              proxyWebsockets = true;
            };
          };
          ${slskdUrl} = {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString slskdPort}";
              proxyWebsockets = true;
            };
          };
        };
      };
  };
}
