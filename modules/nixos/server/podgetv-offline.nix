{ inputs, ... }:
let
  url = "offline.jellyfin.goosebox.org";
in
{
  flake.monitoringChecks.podgetv-offline = {
    name = "podgetv-offline";
    url = "https://${url}/health";
  };

  flake.modules.nixos.podgetv-offline =
    { config, ... }:
    {
      imports = [ inputs.podgetv.nixosModules.offline ];

      services.podgetv-offline = {
        enable = true;
        jellyfinUrl = "https://jellyfin.goosebox.org";
        domain = url;
        dataDir = "${config.blizzard.storage.data}/podgetv-offline";
        keep = "7d";
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
      };
    };
}
