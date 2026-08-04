_:
let
  dataDir = "/storage/data/dmvault";
  # The DM drops a single combined `homebrew.orcbrew` here; every client
  # auto-loads it from the site root on connect (see the nginx location below).
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
      # Character data lives entirely inside Datomic; back up its storage dir.
      # Datomic Free uses an embedded H2 store, so a live copy is crash-
      # consistent enough for this low-write, small-group workload (same
      # approach as actual-budget). The ./logs dir is disposable.
      age.secrets.dmvault-secrets = {
        rekeyFile = ./secrets/dmvault-secrets.age;
        owner = "containers";
      };

      # Own both dirs as `containers` (so rootless podman/datomic can create the
      # DB subdirs) at 0755 (so the `nginx` user can traverse in and read the
      # homebrew file). Ordering is safe: tmpfiles runs at early boot, before the
      # lingering containers-user services start the quadlet units.
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0755 containers containers - -"
        "d ${homebrewDir} 0755 containers containers - -"
      ];

      home-manager.users.containers.virtualisation.quadlet = {
        networks.dmvault.networkConfig = { };

        containers = {
          # The container MUST be named `datomic`: the Orcpub Datomic image's
          # transactor advertises the host `datomic` to peers, and the app's
          # DATOMIC_URL connects to `datomic:4334`. Both must resolve to this
          # container, which podman gives the network alias `datomic` on the
          # shared network. This mirrors the upstream docker-compose service name.
          datomic.containerConfig = {
            # Upstream is unmaintained and only publishes a rolling `latest`.
            image = "docker.io/orcpub/datomic:latest";
            volumes = [
              "${dataDir}/data:/data"
              "${dataDir}/logs:/logs"
            ];
            # Provides ADMIN_PASSWORD + DATOMIC_PASSWORD.
            environmentFiles = [ config.age.secrets.dmvault-secrets.path ];
            networks = [ "dmvault.network" ];
            noNewPrivileges = true;
          };

          dmvault-app = {
            containerConfig = {
              image = "docker.io/orcpub/orcpub:latest";
              publishPorts = [ "127.0.0.1:${toString port}:${toString port}" ];
              # Provides DATOMIC_URL (embeds the DB password), SIGNATURE, and
              # EMAIL_SECRET_KEY (the Resend API key) — all sensitive.
              environmentFiles = [ config.age.secrets.dmvault-secrets.path ];
              environments = {
                PORT = toString port;
                # Resend transactional relay over STARTTLS on 587.
                EMAIL_SERVER_URL = "smtp.resend.com";
                EMAIL_SERVER_PORT = "587";
                EMAIL_ACCESS_KEY = "resend";
                # Must be on the exact domain verified in Resend (email.goosebox.org),
                # or Resend rejects the send as an unverified sender.
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
        # Orcpub clients fetch shared homebrew from the site root as
        # `/homebrew.orcbrew` and auto-load it — so the DM curates books once
        # here instead of every player importing them. `root` + this exact URI
        # resolves to `${homebrewDir}/homebrew.orcbrew` (mirrors upstream nginx).
        locations."= /homebrew.orcbrew".root = homebrewDir;
      };
    };
}
