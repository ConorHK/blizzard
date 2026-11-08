{
  flake.modules.nixos.matrix-gateway =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.matrix-gateway;
    in
    {
      age.secrets.matrix-gateway-env.rekeyFile = ./secrets/matrix-gateway-env.age;

      systemd.services.matrix-gateway = {
        description = "Matrix gateway for the local assistant";
        after = [
          "matrix-synapse.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "matrix-synapse.service" ];
        wantedBy = [ "multi-user.target" ];

        environment = {
          MATRIX_HOMESERVER = "http://127.0.0.1:8008";
          MATRIX_USER = "assistant";
          MATRIX_ADMIN = "@conor:matrix.goosebox.org";
          MATRIX_DATABASE = "/var/lib/matrix-gateway/crypto.db";
        };

        serviceConfig = {
          ExecStart = lib.getExe package;
          EnvironmentFile = config.age.secrets.matrix-gateway-env.path;
          Restart = "on-failure";
          RestartSec = 30;

          DynamicUser = true;
          StateDirectory = "matrix-gateway";
          StateDirectoryMode = "0700";
          CapabilityBoundingSet = [ "" ];
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          PrivateUsers = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
        };
      };
    };
}
