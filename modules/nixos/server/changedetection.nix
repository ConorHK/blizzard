_:
let
  dataDir = "/storage/data/changedetection";
  url = "changedetection.lep.goosebox.org";
  port = 5000;
in
{
  flake.monitoringChecks.changedetection = {
    name = "changedetection";
    url = "https://${url}";
  };

  flake.modules.nixos.changedetection = {
    home-manager.users.containers.virtualisation.quadlet = {
      networks.changedetection.networkConfig = { };

      containers = {
        changedetection-browser.containerConfig = {
          # renovate: datasource=docker depName=docker.io/dgtlmoon/sockpuppetbrowser
          image = "docker.io/dgtlmoon/sockpuppetbrowser:0.0.3";
          # Chrome's namespace sandbox needs it; rootless, so it is not host root.
          addCapabilities = [ "SYS_ADMIN" ];
          # Chrome crashes on podman's 64M default /dev/shm.
          shmSize = "1g";
          environments = {
            SCREEN_WIDTH = "1920";
            SCREEN_HEIGHT = "1024";
            MAX_CONCURRENT_CHROME_PROCESSES = "4";
          };
          networks = [ "changedetection.network" ];
          noNewPrivileges = true;
        };

        changedetection = {
          containerConfig = {
            # renovate: datasource=docker depName=ghcr.io/dgtlmoon/changedetection.io
            image = "ghcr.io/dgtlmoon/changedetection.io:0.55.8";
            publishPorts = [ "127.0.0.1:${toString port}:5000" ];
            volumes = [ "${dataDir}:/datastore" ];
            environments = {
              BASE_URL = "https://${url}";
              PLAYWRIGHT_DRIVER_URL = "ws://changedetection-browser:3000";
              USE_X_SETTINGS = "1";
              HIDE_REFERER = "true";
              DISABLE_VERSION_CHECK = "true";
              LLM_FEATURES_DISABLED = "true";
              TZ = "Europe/Dublin";
            };
            networks = [ "changedetection.network" ];
            noNewPrivileges = true;
          };
          unitConfig = {
            After = "changedetection-browser.service";
            Requires = "changedetection-browser.service";
          };
        };
      };
    };

    restic.paths = [ dataDir ];
    # /datastore is JSON plus snapshot blobs written outside any transaction, so a
    # live copy can catch a half-written watch history.
    restic.pauseContainers = [ "changedetection" ];

    services.nginx.virtualHosts.${url} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
    };
  };
}
