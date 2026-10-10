_:
let
  url = "tunarr.goosebox.org";
  port = 8000;
in
{
  flake.monitoringChecks.tunarr = {
    name = "tunarr";
    url = "https://${url}/api/version";
  };

  flake.modules.nixos.tunarr =
    { config, ... }:
    let
      inherit (config.blizzard.storage) data media;
      dataDir = "${data}/tunarr";
    in
    {
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0750 containers containers -"
        "d ${media}/bumpers 0775 containers containers -"
      ];

      home-manager.users.containers.virtualisation.quadlet.containers.tunarr.containerConfig = {
        # renovate: datasource=docker depName=docker.io/chrisbenincasa/tunarr
        image = "docker.io/chrisbenincasa/tunarr:2026.10.1";
        publishPorts = [ "127.0.0.1:${toString port}:8000" ];
        volumes = [
          "${dataDir}:/config/tunarr"
          # Same paths as Jellyfin, for direct file access.
          "${media}/movies:/data/movies:ro"
          "${media}/tv:/data/tv:ro"
          "${media}/bumpers:/data/bumpers:ro"
        ];
        devices = [ "nvidia.com/gpu=all" ];
        environments = {
          TZ = "Europe/Dublin";
          TUNARR_SERVER_TRUST_PROXY = "true";
        };
        # Jellyfin and Tunarr reach each other by name.
        networks = [ "jellyfin.network" ];
        noNewPrivileges = true;
      };

      # Stopped for a consistent SQLite copy.
      restic.paths = [ dataDir ];
      restic.pauseContainers = [ "tunarr" ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
          extraConfig = "proxy_buffering off;";
        };
      };
    };
}
