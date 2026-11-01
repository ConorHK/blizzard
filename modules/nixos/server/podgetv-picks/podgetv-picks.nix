{ inputs, ... }:
let
  url = "picks.jellyfin.goosebox.org";
in
{
  flake.monitoringChecks.podgetv-picks = {
    name = "podgetv-picks";
    url = "https://${url}/health";
  };

  flake.modules.nixos.podgetv-picks =
    { config, ... }:
    {
      imports = [ inputs.podgetv.nixosModules.picks ];

      age.secrets.podgetv-seerr-key.rekeyFile = ./secrets/podgetv-seerr-key.age;

      services.podgetv-picks = {
        enable = true;
        jellyfinUrl = "https://jellyfin.goosebox.org";
        seerrUrl = "http://127.0.0.1:5055";
        seerrKeyFile = config.age.secrets.podgetv-seerr-key.path;
        port = 8093;
        domain = url;
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
      };
    };
}
