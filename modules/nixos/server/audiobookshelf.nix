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
    url = "https://${url}";
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

    restic.paths = [ "${configDir}/config" ];

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
