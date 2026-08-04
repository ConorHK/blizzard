{ lib, ... }:
let
  configDir = "/storage/data/audiobookshelf";
  mediaDir = "/storage/media";
  url = "audiobookshelf.goosebox.org";
  port = "13378";
in
{
  flake.monitoringChecks.audiobookshelf = {
    name = "audiobookshelf";
    # `/healthcheck` is a bare 200; `/` serves the whole client app, which is
    # what timed out under backup I/O.
    url = "https://${url}/healthcheck";
    timeout = "30s";
    # Covers the 03:00 restic run, overlapping the 06:00 global reboot window
    # so there's no gap between the two.
    maintenanceWindows = [
      {
        start = "02:55";
        duration = "195m";
      }
    ];
  };
  flake.modules.nixos.audiobookshelf = {
    networking.firewall.allowedTCPPorts = [ (lib.toInt port) ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.audiobookshelf.networkConfig = { };

      containers.audiobookshelf.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/advplyr/audiobookshelf
        image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
        publishPorts = [ "127.0.0.1:${port}:80" ];
        volumes = [
          "${mediaDir}/audiobooks:/audiobooks"
          "${mediaDir}/podcasts:/podcasts"
          "${configDir}/config:/config"
          "${configDir}/metadata:/metadata"
        ];
        environments.TZ = "Europe/Dublin";
        networks = [ "audiobookshelf.network" ];
        noNewPrivileges = true;
      };
    };

    # Back up ABS's own consistent {sqlite + covers} snapshot, not the live /config
    restic.paths = [ "${configDir}/metadata/backups" ];

    services.nginx.virtualHosts."${url}" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${port}";
        proxyWebsockets = true;
        extraConfig = "client_max_body_size 0;";
      };
    };
  };
}
