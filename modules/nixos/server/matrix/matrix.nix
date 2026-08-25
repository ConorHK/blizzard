_:
let
  serverName = "matrix.goosebox.org";
  adminUser = "@conor:${serverName}";
  dataDir = "/storage/matrix";
  synapsePort = 8008;
  homeserver = {
    domain = serverName;
    address = "http://127.0.0.1:${toString synapsePort}";
  };
  permissions = {
    "*" = "relay";
    ${serverName} = "user";
    ${adminUser} = "admin";
  };
in
{
  # libolm is deprecated; every mautrix bridge still links it.
  nixpkgs.allowedInsecurePackages = [ "olm-3.2.16" ];

  flake.monitoringChecks.matrix = {
    name = "matrix";
    url = "https://${serverName}/_matrix/client/versions";
  };

  flake.modules.nixos.matrix =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      dbDump = pkgs.writeShellApplication {
        name = "matrix-db-dump";
        runtimeInputs = [
          config.services.postgresql.package
          pkgs.sqlite
          pkgs.gzip
          pkgs.util-linux
          pkgs.coreutils
        ];
        text = ''
          dir=${dataDir}/dumps
          mkdir -p "$dir"

          runuser -u matrix-synapse -- pg_dump --clean --if-exists matrix-synapse \
            | gzip >"$dir/synapse.sql.gz.tmp"
          mv -f "$dir/synapse.sql.gz.tmp" "$dir/synapse.sql.gz"

          # Live SQLite copies tear; .backup does not.
          snapshot() {
            [ -f "$1" ] || return 0
            sqlite3 "$1" ".backup '$2'"
          }
          snapshot /var/lib/mautrix-whatsapp/mautrix-whatsapp.db "$dir/whatsapp.db"
          snapshot /var/lib/mautrix-discord/mautrix-discord.db "$dir/discord.db"
          snapshot /var/lib/mautrix-meta-facebook/mautrix-meta.db "$dir/facebook.db"
          snapshot /var/lib/mautrix-meta-instagram/mautrix-meta.db "$dir/instagram.db"
        '';
      };
    in
    {
      age.secrets = {
        matrix-synapse-secrets = {
          rekeyFile = ./secrets/matrix-synapse-secrets.age;
          owner = "matrix-synapse";
        };
        mautrix-whatsapp-env = {
          rekeyFile = ./secrets/mautrix-whatsapp-env.age;
          owner = "mautrix-whatsapp";
        };
        mautrix-discord-env = {
          rekeyFile = ./secrets/mautrix-discord-env.age;
          owner = "mautrix-discord";
        };
      };

      systemd = {
        # Root-owned parent: tmpfiles refuses unsafe owner transitions.
        tmpfiles.rules = [
          "d ${dataDir} 0755 root root -"
          # setgid: new media inherits the backup user's group.
          "d ${dataDir}/media_store 2750 matrix-synapse containers -"
          "d ${dataDir}/dumps 0750 root containers -"
        ];

        services = {
          # Group-readable so the `containers` backup user reads media_store.
          matrix-synapse.serviceConfig.UMask = lib.mkForce "0027";

          matrix-db-dump = {
            description = "Dump Synapse and bridge databases";
            serviceConfig = {
              Type = "oneshot";
              Group = "containers";
              UMask = "0027";
              ExecStart = lib.getExe dbDump;
            };
          };
        };

        timers.matrix-db-dump = {
          description = "Nightly Matrix database dump";
          # Ahead of the 03:00 restic run.
          timerConfig = {
            OnCalendar = "02:30";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      };

      services = {
        # Synapse requires C collation; ensureDatabases cannot set it.
        postgresql = {
          enable = true;
          initialScript = pkgs.writeText "synapse-init.sql" ''
            CREATE ROLE "matrix-synapse" WITH LOGIN;
            CREATE DATABASE "matrix-synapse" WITH OWNER "matrix-synapse"
              TEMPLATE template0
              LC_COLLATE = "C"
              LC_CTYPE = "C";
          '';
        };

        matrix-synapse = {
          enable = true;
          extraConfigFiles = [ config.age.secrets.matrix-synapse-secrets.path ];
          settings = {
            server_name = serverName;
            public_baseurl = "https://${serverName}";
            enable_registration = false;
            media_store_path = "${dataDir}/media_store";
            database.name = "psycopg2";
            # Empty whitelist blocks all federation.
            federation_domain_whitelist = [ ];
            listeners = [
              {
                port = synapsePort;
                bind_addresses = [ "127.0.0.1" ];
                type = "http";
                tls = false;
                x_forwarded = true;
                resources = [
                  {
                    names = [ "client" ];
                    compress = true;
                  }
                ];
              }
            ];
          };
        };

        mautrix-whatsapp = {
          enable = true;
          environmentFile = config.age.secrets.mautrix-whatsapp-env.path;
          settings = {
            inherit homeserver;
            appservice.hostname = "localhost";
            bridge.permissions = permissions;
            provisioning.shared_secret = "disable";
            encryption = {
              allow = true;
              default = true;
              require = true;
              pickle_key = "$MAUTRIX_WHATSAPP_PICKLE_KEY";
            };
          };
        };

        mautrix-discord = {
          enable = true;
          environmentFile = config.age.secrets.mautrix-discord-env.path;
          settings = {
            inherit homeserver;
            appservice.hostname = "localhost";
            bridge = {
              inherit permissions;
              encryption = {
                allow = true;
                default = true;
                require = true;
                pickle_key = "$MAUTRIX_DISCORD_PICKLE_KEY";
              };
            };
          };
        };

        # facebook/instagram presets carry mode, id, bot and port.
        mautrix-meta.instances = {
          facebook = {
            enable = true;
            settings = {
              inherit homeserver;
              bridge.permissions = permissions;
            };
          };
          instagram = {
            enable = true;
            settings = {
              inherit homeserver;
              bridge.permissions = permissions;
            };
          };
        };

        nginx.virtualHosts.${serverName} = {
          enableACME = true;
          forceSSL = true;
          extraConfig = ''
            client_max_body_size 100M;
          '';
          locations = {
            "/".return = "404";
            "/_matrix".proxyPass = "http://127.0.0.1:${toString synapsePort}";
            "/_synapse/client".proxyPass = "http://127.0.0.1:${toString synapsePort}";
            "= /.well-known/matrix/client".extraConfig = ''
              default_type application/json;
              add_header Access-Control-Allow-Origin *;
              return 200 '{"m.homeserver":{"base_url":"https://${serverName}"}}';
            '';
          };
        };
      };

      restic.paths = [
        "${dataDir}/dumps"
        "${dataDir}/media_store"
      ];
    };
}
