_: {
  flake.modules.nixos.freshrss = _: {
    networking.firewall.allowedTCPPorts = [ 8002 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.freshrss.networkConfig = { };

      containers.freshrss.containerConfig = {
        # renovate: datasource=docker depName=freshrss/freshrss
        image = "freshrss/freshrss:latest";
        publishPorts = [ "8002:80" ];
        volumes = [
          "/storage/data/freshrss/data:/var/www/FreshRSS/data"
          "/storage/data/freshrss/extensions:/var/www/FreshRSS/extensions"
        ];
        environments = {
          TZ = "Europe/Dublin";
          CRON_MIN = "3,33";
          TRUSTED_PROXY = "172.16.0.1/12 192.168.0.1/16";
        };
        networks = [ "freshrss.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."rss.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8002";
        proxyWebsockets = true;
      };
    };
  };
}
