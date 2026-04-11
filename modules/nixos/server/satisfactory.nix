_: {
  flake.modules.nixos.satisfactory = _: {
    networking.firewall = {
      allowedTCPPorts = [
        7777
        8888
      ];
      allowedUDPPorts = [ 7777 ];
    };

    home-manager.users.containers.virtualisation.quadlet = {
      networks.satisfactory.networkConfig = { };

      containers.satisfactory.autoStart = false;

      containers.satisfactory.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/wolveix/satisfactory-server
        image = "ghcr.io/wolveix/satisfactory-server:v1.9.10";
        publishPorts = [
          "7777:7777/tcp"
          "7777:7777/udp"
          "8888:8888/tcp"
        ];
        volumes = [ "/storage/data/satisfactory-server/data:/config" ];
        environments = {
          AUTOPAUSE = "false";
          AUTOSAVE = "true";
          AUTOSAVENUM = "3";
          AUTOSAVEINTERVAL = "300";
          MAXPLAYERS = "8";
        };
        networks = [ "satisfactory.network" ];
        noNewPrivileges = true;
      };
    };
  };
}
