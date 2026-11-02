_: {
  flake.modules.nixos.revolut-import =
    { config, pkgs, ... }:
    let
      port = 8097;

      app = pkgs.buildNpmPackage {
        pname = "revolut-import";
        version = "0.1.0";
        src = ./src;
        npmDeps = pkgs.importNpmLock { npmRoot = ./src; };
        inherit (pkgs.importNpmLock) npmConfigHook;
        # better-sqlite3 compiles its bundled SQLite during npm rebuild.
        nativeBuildInputs = [ pkgs.python3 ];
        dontNpmBuild = true;
        doCheck = true;
        checkPhase = ''
          runHook preCheck
          node --test
          runHook postCheck
        '';
        meta.mainProgram = "revolut-import";
      };

      settings = (pkgs.formats.json { }).generate "revolut-import.json" {
        # Only the phone, over wg0, can reach this address.
        host = "10.100.0.1";
        inherit port;
        serverURL = "http://127.0.0.1:5006";
        syncId = "5eeed1e8-59c2-4c7f-92cb-1079f755d84f";
        dataDir = "/var/lib/revolut-import";
        # Revolut Product column to Actual account name.
        accounts = {
          Current = "revolut-euro";
        };
        # Credit card exports have no Product column.
        defaultAccount = "rev-credit";
        # Spend notifications without available credit come from the euro account.
        spendAccount = "revolut-euro";
      };
    in
    {
      age.secrets = {
        revolut-import-token.rekeyFile = ./secrets/token.age;
        revolut-import-actual-password.rekeyFile = ./secrets/actual-password.age;
      };

      systemd.services.revolut-import = {
        description = "Import Revolut CSVs into Actual";
        wantedBy = [ "multi-user.target" ];
        # The listen address exists only while wg0 is up.
        requires = [ "wireguard-wg0.service" ];
        after = [ "wireguard-wg0.service" ];
        serviceConfig = {
          ExecStart = "${pkgs.lib.getExe app} ${settings}";
          LoadCredential = [
            "token:${config.age.secrets.revolut-import-token.path}"
            "actual-password:${config.age.secrets.revolut-import-actual-password.path}"
          ];
          DynamicUser = true;
          StateDirectory = "revolut-import";
          StateDirectoryMode = "0700";
          Restart = "on-failure";
          RestartSec = 10;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
        };
      };
    };
}
