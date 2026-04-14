_: {
  flake.modules.nixos.music = _: {
    networking.firewall.allowedTCPPorts = [
      4747 # gonic (subsonic-compatible music server)
      5274 # octo-fiesta (music downloader)
      5030 # slskd web UI
      5031 # slskd API
      50300 # slskd transfer port
    ];

    home-manager.users.containers.virtualisation.quadlet = {
      networks.music.networkConfig = { };

      containers = {
        gonic.containerConfig = {
          # renovate: datasource=docker depName=sentriz/gonic
          image = "sentriz/gonic:latest";
          publishPorts = [ "127.0.0.1:4747:80" ];
          volumes = [
            "/storage/data/gonic/data:/data"
            "/storage/media/music:/music:ro"
            "/storage/data/gonic/playlists:/playlists"
            "/storage/data/gonic/cache:/cache"
          ];
          environments = {
            TZ = "Europe/Dublin";
          };
          networks = [ "music.network" ];
          noNewPrivileges = true;
        };

        octo-fiesta.containerConfig = {
          # renovate: datasource=docker depName=ghcr.io/v1ck3s/octo-fiesta
          image = "ghcr.io/v1ck3s/octo-fiesta:latest";
          publishPorts = [ "127.0.0.1:5274:8080" ];
          volumes = [ "/storage/media/music:/app/downloads" ];
          environments = {
            ASPNETCORE_ENVIRONMENT = "Production";
            Library__DownloadPath = "/app/downloads";
            Subsonic__Url = "http://gonic:80";
            Subsonic__MusicService = "SquidWTF";
            Subsonic__StorageMode = "Permanent";
            Subsonic__EnableExternalPlaylists = "true";
            Subsonic__PlaylistsDirectory = "playlists";
            Subsonic__ExplicitFilter = "All";
            Subsonic__DownloadMode = "Track";
            Subsonic__AutoUpgradeQuality = "false";
            SquidWTF__Source = "Qobuz";
            SquidWTF__InstanceTimeoutSeconds = "5";
          };
          networks = [ "music.network" ];
          noNewPrivileges = true;
        };

        slskd.containerConfig = {
          # renovate: datasource=docker depName=slskd/slskd
          image = "slskd/slskd:latest";
          publishPorts = [
            "127.0.0.1:5030:5030"
            "5031:5031"
            "50300:50300"
          ];
          volumes = [
            "/storage/data/slskd:/app"
            "/storage/media/music:/music:rw"
          ];
          environments = {
            SLSKD_REMOTE_CONFIGURATION = "true";
          };
          user = "1000:1000";
          networks = [ "music.network" ];
          noNewPrivileges = true;
        };
      };
    };

    services.nginx.virtualHosts = {
      "music.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:4747";
          proxyWebsockets = true;
        };
      };
      "slskd.goosebox.org" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:5030";
          proxyWebsockets = true;
        };
      };
    };
  };
}
