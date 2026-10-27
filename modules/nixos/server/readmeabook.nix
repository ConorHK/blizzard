{ lib, ... }:
let
  # One instance per household, separate DBs.
  instances = {
    conor = {
      url = "requestbook.goosebox.org";
      port = 3030;
    };
    toni = {
      url = "mom.request.goosebox.org";
      port = 3029;
    };
  };
in
{
  flake = {
    monitoringChecks = lib.mapAttrs' (
      name: i:
      lib.nameValuePair "readmeabook-${name}" {
        name = "readmeabook-${name}";
        url = "https://${i.url}/api/health";
      }
    ) instances;

    modules.nixos.readmeabook =
      { config, ... }:
      let
        inherit (config.blizzard.storage) data media;
        dataDir = "${data}/readmeabook";
        # Bind sources podman needs present.
        binds = [
          "config"
          "cache"
          "pgdata"
          "redis"
        ];
      in
      {
        # ":" sets owner and mode only on creation.
        systemd.tmpfiles.rules = lib.concatMap (
          name:
          [ "d ${dataDir}/${name} 0750 containers containers -" ]
          ++ map (bind: "d ${dataDir}/${name}/${bind} :0750 :containers :containers -") binds
        ) (lib.attrNames instances);

        home-manager.users.containers.virtualisation.quadlet.containers = lib.mapAttrs' (
          name: i:
          lib.nameValuePair "readmeabook-${name}" {
            containerConfig = {
              # renovate: datasource=docker depName=ghcr.io/kikootwo/readmeabook
              image = "ghcr.io/kikootwo/readmeabook:1.2.11";
              publishPorts = [ "127.0.0.1:${toString i.port}:3030" ];
              volumes = [
                # Same /data/torrents path as qbittorrent.
                "${media}/torrents:/data/torrents"
                "${media}/audiobooks:/media"
                "${dataDir}/${name}/config:/app/config"
                "${dataDir}/${name}/cache:/app/cache"
                "${dataDir}/${name}/pgdata:/var/lib/postgresql/data"
                "${dataDir}/${name}/redis:/var/lib/redis"
              ];
              environments = {
                # Container root is the host containers user.
                PUID = "0";
                PGID = "0";
                PUBLIC_URL = "https://${i.url}";
                TZ = "Europe/Dublin";
              };
              # Reaches qbittorrent (gluetun) and prowlarr by name.
              networks = [ "arr.network" ];
              noNewPrivileges = true;
            };
          }
        ) instances;

        services.nginx.virtualHosts = lib.mapAttrs' (
          _: i:
          lib.nameValuePair i.url {
            enableACME = true;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString i.port}";
              proxyWebsockets = true;
            };
          }
        ) instances;
      };
  };
}
