_: {
  flake.modules.nixos.actual-budget =
    let
      dataDir = "/storage/data/actual-budget";
    in
    {
      networking.firewall.allowedTCPPorts = [ 5006 ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.actual-budget.networkConfig = { };

        containers.actual-budget.containerConfig = {
          # renovate: datasource=docker depName=docker.io/actualbudget/actual-server
          image = "docker.io/actualbudget/actual-server:26.4.0";
          publishPorts = [ "5006:5006" ];
          volumes = [ "${dataDir}:/data" ];
          networks = [ "actual-budget.network" ];
          noNewPrivileges = true;
        };

        containers.backrest.containerConfig.volumes = [
          "${dataDir}:/userdata/actual-budget"
        ];
      };

      services.nginx.virtualHosts."budget.lep.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:5006";
          proxyWebsockets = true;
          extraConfig = ''
            add_header Cross-Origin-Opener-Policy "same-origin";
            add_header Cross-Origin-Embedder-Policy "require-corp";
          '';
        };
      };
    };
}
