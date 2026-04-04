_: {
  flake.modules.nixos.actual-budget = _: {
    networking.firewall.allowedTCPPorts = [ 5006 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.actual-budget.networkConfig = { };

      containers.actual-budget.containerConfig = {
        # renovate: datasource=docker depName=docker.io/actualbudget/actual-server
        image = "docker.io/actualbudget/actual-server:latest";
        publishPorts = [ "5006:5006" ];
        volumes = [ "/storage/data/actual-budget:/data" ];
        networks = [ "actual-budget.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."budget.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:5006";
        proxyWebsockets = true;
      };
    };
  };
}
