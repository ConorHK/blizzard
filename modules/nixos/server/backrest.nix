_: {
  flake.modules.nixos.backrest = _: {
    networking.firewall.allowedTCPPorts = [ 9898 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.backrest.networkConfig = { };

      containers.backrest.containerConfig = {
        # renovate: datasource=docker depName=garethgeorge/backrest
        image = "garethgeorge/backrest:latest";
        publishPorts = [ "9898:9898" ];
        volumes = [
          "/storage/data/backrest/data:/data"
          "/storage/data/backrest/config:/config"
          "/storage/data/backrest/cache:/cache"
          # Mount storage for backup source access
          "/storage:/userdata/storage"
          # Podman socket for container-aware backups (rootless user socket)
          "/run/user/1000/podman/podman.sock:/var/run/docker.sock:ro"
        ];
        environments = {
          PUID = "1000";
          PGID = "1000";
          BACKREST_DATA = "/data";
          BACKREST_CONFIG = "/config/config.json";
          XDG_CACHE_HOME = "/cache";
          TZ = "Europe/Dublin";
        };
        networks = [ "backrest.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."backrest.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:9898";
        proxyWebsockets = true;
      };
    };
  };
}
