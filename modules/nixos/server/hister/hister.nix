_:
let
  url = "search.goosebox.org";
in
{
  flake.monitoringChecks.hister = {
    name = "hister";
    url = "https://${url}";
  };

  flake.modules.nixos.hister =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      dataDir = "${config.blizzard.storage.data}/hister";
      stateDir = "${dataDir}/.config/hister";
      dbs = [
        "db.sqlite3"
        "vectors.sqlite3"
      ];
      dumpDir = "${config.blizzard.storage.data}/hister-dumps";

      dump = pkgs.writeShellApplication {
        name = "hister-db-dump";
        runtimeInputs = [
          pkgs.sqlite
          pkgs.coreutils
        ];
        text = ''
          for db in ${lib.escapeShellArgs dbs}; do
            # sqlite3 would create an empty file.
            [ -s "${stateDir}/$db" ] || { echo "missing ${stateDir}/$db" >&2; exit 1; }
            sqlite3 "${stateDir}/$db" ".backup '${dumpDir}/$db.tmp'"
            mv -f "${dumpDir}/$db.tmp" "${dumpDir}/$db"
          done
        '';
      };
    in
    {
      users = {
        users.hister = {
          isSystemUser = true;
          group = "hister";
          home = dataDir;
        };
        groups.hister = { };
      };

      age.secrets.hister-access-token.rekeyFile = ./secrets/hister-access-token.age;

      systemd = {
        # setgid: new files inherit the backup user's group.
        tmpfiles.rules = [
          "d ${dataDir} 2750 hister containers -"
          "d ${dumpDir} 2750 hister containers -"
        ];

        services.hister = {
          description = "Hister personal search engine";
          after = [
            "network-online.target"
            "ollama.service"
          ];
          wants = [
            "network-online.target"
            "ollama.service"
          ];
          wantedBy = [ "multi-user.target" ];

          environment = {
            HOME = dataDir;
            HISTER__SERVER__BASE_URL = "https://${url}";
            HISTER__APP__SEARCH_URL = "https://kagi.com/search?q={query}";
            HISTER__SEMANTIC_SEARCH__ENABLE = "true";
            HISTER__SEMANTIC_SEARCH__EMBEDDING_ENDPOINT = "http://127.0.0.1:11434/v1/embeddings";
            HISTER__SEMANTIC_SEARCH__EMBEDDING_MODEL = "nomic-embed-text";
            HISTER__SEMANTIC_SEARCH__DIMENSIONS = "768";
            # Nomic wants search_query/search_document prefixes.
            HISTER__SEMANTIC_SEARCH__QUERY_PREFIX = "search_query: ";
            HISTER__SEMANTIC_SEARCH__DOCUMENT_PREFIX = "search_document: ";
          };

          serviceConfig = {
            User = "hister";
            Group = "hister";
            # Group-readable so the `containers` backup user reads the index.
            UMask = "0027";
            ExecStart = "${lib.getExe pkgs.hister} listen --address 127.0.0.1:4433";
            EnvironmentFile = config.age.secrets.hister-access-token.path;
            WorkingDirectory = dataDir;
            Restart = "on-failure";
            RestartSec = "5s";

            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ReadWritePaths = [ dataDir ];
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            LockPersonality = true;
            RestrictRealtime = true;
          };
        };

        services.hister-db-dump = {
          description = "Dump the Hister database";
          unitConfig.OnFailure = "alert-failure@hister-db-dump.service";
          serviceConfig = {
            Type = "oneshot";
            User = "hister";
            Group = "hister";
            UMask = "0027";
            ExecStart = lib.getExe dump;
          };
        };

        timers.hister-db-dump = {
          description = "Daily Hister database dump";
          # Ahead of the 03:00 restic run.
          timerConfig = {
            OnCalendar = "02:45";
            Persistent = true;
          };
          wantedBy = [ "timers.target" ];
        };
      };

      restic = {
        paths = [ dataDir ];
        dumpPaths = [ dumpDir ];
        # A live copy can tear; the dump replaces it.
        # `hister reindex` rebuilds the index dirs.
        exclude = map (db: "${stateDir}/${db}*") dbs ++ [ "${stateDir}/index*.db" ];
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:4433";
          proxyWebsockets = true;
        };
      };
    };
}
