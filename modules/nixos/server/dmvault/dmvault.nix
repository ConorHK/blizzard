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

      # Create every bind-mount source up front. Rootless podman 5.x does NOT
      # auto-create missing `-v` source dirs — it fails with `statfs ... no such
      # file or directory` (exit 125) — so datomic's `data`/`logs` must exist
      # before it starts. All owned by `containers` so podman can write, at 0755
      # so the `nginx` user can also traverse in to read the homebrew file.
      # Ordering is safe: tmpfiles runs at early boot, before the lingering
      # containers-user services start the quadlet units.
      systemd.tmpfiles.rules = [
        "d ${dataDir} 0755 containers containers - -"
        "d ${dataDir}/data 0755 containers containers - -"
        "d ${dataDir}/logs 0755 containers containers - -"
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
            # renovate: datasource=docker depName=docker.io/orcpub/datomic
            image = "docker.io/orcpub/datomic:release-2.4.0.28";
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
              # renovate: datasource=docker depName=docker.io/orcpub/orcpub
              # This repo publishes NO `latest` tag — only `release-*` tags.
              image = "docker.io/orcpub/orcpub:release-v2.5.0.27";
              publishPorts = [ "127.0.0.1:${toString port}:${toString port}" ];
              # Secret provides DATOMIC_PASSWORD, SIGNATURE, and EMAIL_SECRET_KEY
              # (the Resend API key). The DB password is joined to the URL by
              # orcpub itself — config.clj appends `?password=<DATOMIC_PASSWORD>`
              # whenever DATOMIC_URL contains no `password=`.
              environmentFiles = [ config.age.secrets.dmvault-secrets.path ];
              environments = {
                PORT = toString port;
                # Kept in code (not the secret) so the scheme can't be mistyped:
                # orcpub uses this string verbatim, so the mandatory `datomic:`
                # scheme prefix, the `free` protocol (matching the transactor),
                # and the `datomic` host (the DB container's network alias) must
                # all be exact. No password here — orcpub appends it (see above).
                DATOMIC_URL = "datomic:free://datomic:4334/orcpub";
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
