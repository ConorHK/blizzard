_:
let
  url = "search.goosebox.org";

  # ACL grants backup reads; hister keeps ownership.
  histerDataRules = dataDir: [
    "d ${dataDir} 2750 hister containers -"
    # Repair stray ownership, keep modes.
    "Z ${dataDir} - hister containers -"
    # Backup user reads via ACL.
    "A+ ${dataDir} - - - - u:containers:rX"
    "A+ ${dataDir} - - - - d:u:containers:rX"
    # Re-grants after chmod squashes the mask.
    "A+ ${dataDir} - - - - m::rX"
  ];
in
{
  flake.testSupport.histerDataRules = histerDataRules;

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

      # setgid: new files inherit backup group.
      systemd.tmpfiles.rules = histerDataRules dataDir;

      age.secrets.hister-access-token.rekeyFile = ./secrets/hister-access-token.age;

      systemd.services.hister = {
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

      restic.paths = [ dataDir ];

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
