_:
let
  url = "jellyfin.lep.goosebox.org";
  port = 8096;
in
{
  flake.monitoringChecks.jellyfin = {
    name = "jellyfin";
    url = "https://${url}/health";
  };

  flake.modules.nixos.jellyfin =
    { config, ... }:
    let
      inherit (config.blizzard.storage) data media;
      dataDir = "${data}/jellyfin";
    in
    {
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${dataDir}/config 0750 containers containers -"
        "d ${dataDir}/cache 0750 containers containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.jellyfin.networkConfig = { };

        containers.jellyfin.containerConfig = {
          # renovate: datasource=docker depName=docker.io/jellyfin/jellyfin
          image = "docker.io/jellyfin/jellyfin:12.2";
          publishPorts = [ "127.0.0.1:${toString port}:8096" ];
          volumes = [
            "${dataDir}/config:/config"
            "${dataDir}/cache:/cache"
            "${media}/movies:/data/movies:ro"
            "${media}/tv:/data/tv:ro"
          ];
          devices = [ "nvidia.com/gpu=all" ];
          environments.TZ = "Europe/Dublin";
          networks = [ "jellyfin.network" ];
          noNewPrivileges = true;
        };
      };

      # Stopped for a consistent SQLite copy.
      restic.paths = [ "${dataDir}/config" ];
      restic.pauseContainers = [ "jellyfin" ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          # Stream video without buffering it to disk.
          extraConfig = "proxy_buffering off;";
        };
      };
    };
}
