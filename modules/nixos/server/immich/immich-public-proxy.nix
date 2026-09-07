_:
let
  # Immich runs on server, not leprechaun.
  immichUrl = "http://100.66.244.36:2283";
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
        networks.immich-public-proxy.networkConfig = { };

        containers.immich-public-proxy.containerConfig = {
          # renovate: datasource=docker depName=docker.io/alangrainger/immich-public-proxy
          image = "docker.io/alangrainger/immich-public-proxy:3.3.1";
          publishPorts = [ "127.0.0.1:${port}:3000" ];
          volumes = [ "${configFile}:/app/config.json:ro" ];
          # Unset PUBLIC_BASE_URL: previews follow request Host.
          environments.IMMICH_URL = immichUrl;
          networks = [ "immich-public-proxy.network" ];
          noNewPrivileges = true;
        };
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        # Share paths only; no Immich here.
        locations = {
          "/".return = "404";
          "/share".proxyPass = "http://127.0.0.1:${port}";
          "/s".proxyPass = "http://127.0.0.1:${port}";
        };
      };
    };
}
