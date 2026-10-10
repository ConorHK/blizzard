_: {
  flake.modules.nixos.arr-backup =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.blizzard.storage) data;
      dumpDir = "${data}/arr-dumps";

      # Paths relative to each app's config dir.
      apps = {
        sonarr = {
          db = "sonarr.db";
          config = "config.xml";
        };
        radarr = {
          db = "radarr.db";
          config = "config.xml";
        };
        lidarr = {
          db = "lidarr.db";
          config = "config.xml";
        };
        prowlarr = {
          db = "prowlarr.db";
          config = "config.xml";
        };
        bazarr = {
          db = "db/bazarr.db";
          config = "config/config.yaml";
        };
        autobrr = {
          db = "autobrr.db";
          config = "config.toml";
        };
        qui = {
          db = "qui.db";
          config = "config.toml";
        };
      };

      dump = pkgs.writeShellApplication {
        name = "arr-db-dump";
        runtimeInputs = [
          pkgs.sqlite
          pkgs.coreutils
        ];
        text = ''
          dump() {
            local app=$1 db=$2 conf=$3
            local out=${dumpDir}/$app
            mkdir -p "$out"
            # Online backup API: consistent while the app writes.
            sqlite3 "${data}/$app/$db" ".backup '$out/db.sqlite.tmp'"
            mv -f "$out/db.sqlite.tmp" "$out/db.sqlite"
            cp -f "${data}/$app/$conf" "$out/"
          }
        ''
        + lib.concatStrings (
          lib.mapAttrsToList (app: f: ''
            dump ${app} ${f.db} ${f.config}
          '') apps
        );
      };
    in
    {
      systemd.tmpfiles.rules = [ "d ${dumpDir} 0750 containers containers -" ];

      home-manager.users.containers.systemd.user = {
        services.arr-db-dump = {
          Unit.Description = "Dump arr app databases";
          Service = {
            Type = "oneshot";
            ExecStart = lib.getExe dump;
          };
        };
        timers.arr-db-dump = {
          Unit.Description = "Daily arr database dump";
          # Ahead of the 03:00 restic run.
          Timer = {
            OnCalendar = "02:45";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

      restic.paths = [
        dumpDir
        "${data}/qbittorrent/config"
        "${data}/qbittorrent/data/BT_backup"
      ];
    };
}
