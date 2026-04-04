_: {
  flake.modules.nixos.caldav = _: {
    networking.firewall.allowedTCPPorts = [ 5232 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.caldav.networkConfig = { };

      containers.radicale.containerConfig = {
        # renovate: datasource=docker depName=11notes/radicale
        image = "11notes/radicale:3.1.9";
        publishPorts = [ "5232:5232" ];
        volumes = [
          "/storage/data/radicale/etc:/radicale/etc"
          "/storage/data/radicale/var:/radicale/var"
        ];
        environment = {
          TZ = "Europe/Dublin";
        };
        networks = [ "caldav.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."dav.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:5232";
        proxyWebsockets = true;
      };
    };
  };
}
