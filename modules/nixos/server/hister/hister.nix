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

      systemd.tmpfiles.rules = [ "d ${dataDir} 0700 hister hister -" ];

      age.secrets.hister-access-token.rekeyFile = ./secrets/hister-access-token.age;

      systemd.services.hister = {
        description = "Hister personal search engine";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          HOME = dataDir;
          HISTER__SERVER__BASE_URL = "https://${url}";
        };

        serviceConfig = {
          User = "hister";
          Group = "hister";
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
