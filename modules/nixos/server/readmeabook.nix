_:
let
  dataDir = "/storage/data/readmeabook";
  # renovate: datasource=docker depName=ghcr.io/kikootwo/readmeabook
  image = "ghcr.io/kikootwo/readmeabook:1.2.1";
  portMain = 3030;
  portMom = 3029;
  commonEnv = { };
  commonVolumes = [
    "/storage/media/torrents/downloads:/data/torrents"
    "/storage/media/audiobooks:/media"
  ];
in
{
  flake.modules.nixos.readmeabook = _: {
    networking.firewall.allowedTCPPorts = [
      portMain # readmeabook
      portMom # readmeabook-mom
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.readmeabook.networkConfig = { };

      containers = {
        readmeabook.containerConfig = {
          inherit image;
          publishPorts = [ "127.0.0.1:${toString portMain}:3030" ];
          volumes = commonVolumes ++ [
            "${dataDir}/conor/config:/app/config"
            "${dataDir}/conor/cache:/app/cache"
            "${dataDir}/conor/pgdata:/var/lib/postgresql/data"
            "${dataDir}/conor/redis:/var/lib/redis"
          ];
          environments = commonEnv // {
            PUBLIC_URL = "https://requestbook.goosebox.com";
          };
          networks = [ "readmeabook.network" ];
          noNewPrivileges = true;
        };

        readmeabook-mom.containerConfig = {
          inherit image;
          publishPorts = [ "127.0.0.1:${toString portMom}:3030" ];
          volumes = commonVolumes ++ [
            "${dataDir}/toni/config:/app/config"
            "${dataDir}/toni/cache:/app/cache"
            "${dataDir}/toni/pgdata:/var/lib/postgresql/data"
            "${dataDir}/toni/redis:/var/lib/redis"
          ];
          environments = commonEnv // {
            PUBLIC_URL = "https://mom.request.goosebox.com";
          };
          networks = [ "readmeabook.network" ];
          noNewPrivileges = true;
        };
      };
    };

    services.nginx.virtualHosts = {
      "requestbook.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString portMain}";
          proxyWebsockets = true;
        };
      };
      "moms.requestbook.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString portMom}";
          proxyWebsockets = true;
        };
      };
    };
  };
}
