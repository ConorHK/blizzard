_: {
  flake.modules.nixos.jellyfin = _: {
    home-manager.users.containers.virtualisation.quadlet = {
      containers.jellyfin.containerConfig = {
        # renovate: datasource=docker depName=jellyfin/jellyfin
        image = "jellyfin/jellyfin:latest";
        volumes = [
          "/storage/data/jellyfin/config:/config"
          "/storage/data/jellyfin/cache:/cache"
          "/storage/data/media/movies:/movies:ro"
          "/storage/data/media/television:/television:ro"
          "/storage/data/media/anime:/anime:ro"
        ];
        # Host networking for DLNA/discovery and hardware transcoding device access
        networkMode = "host";
        noNewPrivileges = true;
      };
    };

    services.nginx.virtualHosts."jellyfin.goosebox.org" = {
      enableACME = true;
      forceSSL = true;
      # Jellyfin needs large headers for auth tokens
      extraConfig = ''
        proxy_buffering off;
      '';
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
      };
    };
  };
}
