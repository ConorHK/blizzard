_:
let
  dataDir = "/storage/data/dmvault";
  homebrewDir = "${dataDir}/homebrew";
  url = "dmvault.lep.goosebox.org";
  port = 8890;
in
{
  flake.monitoringChecks.dmvault = {
    name = "dmvault";
    url = "https://${url}";
  };

  flake.modules.nixos.dmvault =
    { config, ... }:
    {
      age.secrets.dmvault-secrets = {
        rekeyFile = ./secrets/dmvault-secrets.age;
        owner = "containers";
      };

      # Rootless podman won't auto-create bind-mount sources, so pre-create them (0755 lets nginx read the homebrew file).
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0755 containers containers - -"
        "d ${dataDir}/data 0755 containers containers - -"
        "d ${dataDir}/logs 0755 containers containers - -"
        "d ${homebrewDir} 0755 containers containers - -"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.dmvault.networkConfig = { };

        containers = {
          # Must be named `datomic`: peers resolve the transactor via this network alias.
          datomic.containerConfig = {
            # renovate: datasource=docker depName=docker.io/orcpub/datomic
            image = "docker.io/orcpub/datomic:release-2.4.0.28";
            hostname = "datomic";
            volumes = [
              "${dataDir}/data:/data"
              "${dataDir}/logs:/logs"
            ];
            environmentFiles = [ config.age.secrets.dmvault-secrets.path ];
            # Image ships host=0.0.0.0 so start.sh never advertises a routable transactor host; force host=datomic.
            environments.ALT_HOST = "datomic";
            entrypoint = "sh";
            exec = [
              "-c"
              "sed -i 's/^host=.*/host=datomic/' /datomic/transactor.properties && exec /datomic/start.sh"
            ];
            networks = [ "dmvault.network" ];
            noNewPrivileges = true;
          };

          dmvault-app = {
            containerConfig = {
              # renovate: datasource=docker depName=docker.io/orcpub/orcpub
              image = "docker.io/orcpub/orcpub:release-v2.5.0.27";
              publishPorts = [ "127.0.0.1:${toString port}:${toString port}" ];
              # orcpub uses DATOMIC_URL verbatim, so the secret embeds the password in it (alongside SIGNATURE and EMAIL_SECRET_KEY).
              environmentFiles = [ config.age.secrets.dmvault-secrets.path ];
              environments = {
                PORT = toString port;
                EMAIL_SERVER_URL = "smtp.resend.com";
                EMAIL_SERVER_PORT = "587";
                EMAIL_ACCESS_KEY = "resend";
                EMAIL_FROM_ADDRESS = "no-reply@email.goosebox.org";
                EMAIL_ERRORS_TO = "admin@goosebox.org";
                EMAIL_SSL = "FALSE";
                EMAIL_TLS = "TRUE";
              };
              networks = [ "dmvault.network" ];
              noNewPrivileges = true;
            };
            unitConfig = {
              After = "datomic.service";
              Requires = "datomic.service";
            };
          };
        };
      };

      restic.paths = [
        "${dataDir}/data"
        homebrewDir
      ];

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString port}";
          proxyWebsockets = true;
        };
        # Clients auto-load shared homebrew from the site root, so map that exact URI to the homebrew dir.
        locations."= /homebrew.orcbrew".root = homebrewDir;
      };
    };
}
