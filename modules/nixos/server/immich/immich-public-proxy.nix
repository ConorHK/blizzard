_:
let
  url = "photos.goosebox.org";
  port = "3010";

  # Metadata is per-field opt-in upstream.
  settings.ipp = {
    allowDownload = 1;

    showMetadata = {
      description = {
        caption = true;
        sidebar = true;
      };
      exif = {
        dateTimeOriginal = true;
        timeZone = true;
        fileName = true;
        dimensions = true;
        fileSize = true;
        make = true;
        model = true;
        lensModel = true;
        exposureTime = true;
        iso = true;
        fNumber = true;
        focalLength = true;
      };
      location = {
        city = true;
        state = true;
        country = true;
        gps = true;
        webLink = true;
      };
    };

    gallery = {
      showExpiryDate = true;
      groupByDate = true;
    };

    lightbox.showDownload = true;
  };
in
{
  flake.monitoringChecks.immich-public-proxy = {
    name = "immich-public-proxy";
    url = "https://${url}/share/healthcheck";
  };

  flake.modules.nixos.immich-public-proxy =
    { pkgs, ... }:
    let
      configFile = pkgs.writeText "ipp-config.json" (builtins.toJSON settings);
    in
    {
      home-manager.users.containers.virtualisation.quadlet = {
        containers.immich-public-proxy.containerConfig = {
          # renovate: datasource=docker depName=docker.io/alangrainger/immich-public-proxy
          image = "docker.io/alangrainger/immich-public-proxy:4.1.0";
          publishPorts = [ "127.0.0.1:${port}:3000" ];
          volumes = [ "${configFile}:/app/config.json:ro" ];
          # Unset PUBLIC_BASE_URL: previews follow request Host.
          environments.IMMICH_URL = "http://immich-server:2283";
          networks = [ "immich.network" ];
          noNewPrivileges = true;
        };
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        # Uploads need no body size limit.
        extraConfig = ''
          client_max_body_size 0;
        '';
        # Share links go to the proxy, the rest to Immich.
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:2283";
            proxyWebsockets = true;
          };
          "/share".proxyPass = "http://127.0.0.1:${port}";
          "/s".proxyPass = "http://127.0.0.1:${port}";
        };
      };
    };
}
