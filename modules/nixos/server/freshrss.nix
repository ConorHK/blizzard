_:
let
  url = "rss.goosebox.org";
  port = 8002;
in
{
  flake.monitoringChecks.freshrss = {
    name = "freshrss";
    url = "https://${url}/i/";
  };

  flake.modules.nixos.freshrss =
    { config, ... }:
    let
      dataDir = "${config.blizzard.storage.data}/freshrss";
    in
    {
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${dataDir}/data :0750 :containers :containers -"
        "d ${dataDir}/extensions :0750 :containers :containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.freshrss.networkConfig = { };

        containers.freshrss.containerConfig = {
          # renovate: datasource=docker depName=docker.io/freshrss/freshrss
          image = "docker.io/freshrss/freshrss:1.30.3";
          publishPorts = [ "127.0.0.1:${toString port}:80" ];
          volumes = [
            "${dataDir}/data:/var/www/FreshRSS/data"
            "${dataDir}/extensions:/var/www/FreshRSS/extensions"
          ];
          environments = {
            TZ = "Europe/Dublin";
            CRON_MIN = "3,33";
            TRUSTED_PROXY = "127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16";
          };
          # Apache runs as www-data; map it to containers.
          # The entrypoint still has to start as root.
          userns = "keep-id:uid=33,gid=33";
          user = "0:0";
          networks = [ "freshrss.network" ];
          noNewPrivileges = true;
        };
      };

      restic.paths = [ dataDir ];
      # SQLite; a live copy can tear.
      restic.pauseContainers = [ "freshrss" ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
        };
      };
    };
}
