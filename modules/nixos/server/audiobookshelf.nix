_: {
  flake.modules.nixos.audiobookshelf = _: {
    networking.firewall.allowedTCPPorts = [ 13378 ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.audiobookshelf.networkConfig = { };

      containers.audiobookshelf.containerConfig = {
        # renovate: datasource=docker depName=ghcr.io/advplyr/audiobookshelf
        image = "ghcr.io/advplyr/audiobookshelf:latest";
        publishPorts = [ "13378:80" ];
        volumes = [
          "/storage/data/media/audiobooks:/audiobooks"
          "/storage/data/media/podcasts:/podcasts"
          "/storage/data/audiobookshelf/config:/config"
          "/storage/data/media/audiobook_metadata:/metadata"
        ];
        networks = [ "audiobookshelf.network" ];
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."audiobooks.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:13378";
        proxyWebsockets = true;
      };
    };
  };
}
