_: {
  config.flake.modules.nixos.backrest =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      mkScript =
        name: cmds:
        pkgs.writeTextFile {
          inherit name;
          executable = true;
          text = ''
            #!/bin/sh
            ${cmds}
          '';
        };
      stopScript = mkScript "backrest-pre-backup" (
        lib.concatMapStringsSep "\n" (
          c: "${pkgs.systemd}/bin/systemctl --user stop ${c}.service"
        ) config.backrest.pauseContainers
      );
      startScript = mkScript "backrest-post-backup" (
        lib.concatMapStringsSep "\n" (
          c: "${pkgs.systemd}/bin/systemctl --user start ${c}.service"
        ) config.backrest.pauseContainers
      );
      # Mount only the store paths in the closure of the hook scripts (which includes
      # systemd and its deps), rather than the entire /nix/store.
      scriptClosurePaths = lib.filter (p: p != "") (
        lib.splitString "\n" (
          builtins.readFile "${
            pkgs.closureInfo {
              rootPaths = [
                stopScript
                startScript
              ];
            }
          }/store-paths"
        )
      );
      closureVolumes = map (p: "${p}:${p}:ro") scriptClosurePaths;
    in
    {
      options.backrest.pauseContainers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Container names to stop before backup and start again after.";
      };

      config = {
        networking.firewall.allowedTCPPorts = [ 9898 ];

        home-manager.users.containers.virtualisation.quadlet = {
          networks.backrest.networkConfig = { };

          containers.backrest.containerConfig = {
            # renovate: datasource=docker depName=garethgeorge/backrest
            image = "garethgeorge/backrest:v1.12.1";
            publishPorts = [ "9898:9898" ];
            volumes = [
              "/storage/data/backrest/data:/data"
              "/storage/data/backrest/config:/config"
              "/storage/data/backrest/cache:/cache"
              "/run/user/1001/bus:/run/user/1001/bus"
              "${stopScript}:/bin/pre-backup"
              "${startScript}:/bin/post-backup"
            ]
            ++ closureVolumes;
            environments = {
              PUID = "1000";
              PGID = "1000";
              BACKREST_DATA = "/data";
              BACKREST_CONFIG = "/config/config.json";
              XDG_CACHE_HOME = "/cache";
              TZ = "Europe/Dublin";
              DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/1001/bus";
            };
            networks = [ "backrest.network" ];
            noNewPrivileges = true;
          };
        };

        services.nginx.virtualHosts."backup.lep.goosebox.org" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://127.0.0.1:9898";
            proxyWebsockets = true;
          };
        };
      };
    };
}
