_:
let
  dataDir = "/storage/data/photon";
  url = "photon.lep.goosebox.org";
  probe = "http://127.0.0.1:2322/reverse?lon=-6.2603&lat=53.3498";
in
{
  flake.monitoringChecks.photon = {
    name = "photon";
    url = "https://${url}/reverse?lon=-6.2603&lat=53.3498";
  };

  flake.modules.nixos.photon =
    { pkgs, ... }:
    let
      refresh = pkgs.writeShellApplication {
        name = "photon-refresh";
        runtimeInputs = [
          pkgs.curl
          pkgs.coreutils
          pkgs.systemd
        ];
        text = ''
          data=${dataDir}
          staging="$data.rebuild"

          systemctl --user stop photon.service
          rm -rf "$staging"
          mv "$data" "$staging"
          mkdir -p "$data"
          systemctl --user start photon.service

          if timeout 16h sh -c 'until curl -sf -o /dev/null "${probe}"; do sleep 60; done'; then
            rm -rf "$staging"
          else
            systemctl --user stop photon.service
            rm -rf "$data"
            mv "$staging" "$data"
            systemctl --user start photon.service
            exit 1
          fi
        '';
      };
    in
    {
      home-manager.users.containers = {
        virtualisation.quadlet = {
          networks.photon.networkConfig = { };

          containers.photon.containerConfig = {
            # renovate: datasource=docker depName=rtuszik/photon-docker
            image = "rtuszik/photon-docker:2.3.1";
            publishPorts = [ "127.0.0.1:2322:2322" ];
            volumes = [ "${dataDir}:/photon/data" ];
            environments = {
              REGION = "planet";
              IMPORT_MODE = "jsonl";
              REVERSE_ONLY = "TRUE";
            };
            networks = [ "photon.network" ];
            noNewPrivileges = true;
          };
        };

        systemd.user = {
          services.photon-refresh = {
            Unit.Description = "Rebuild the Photon planet index";
            Service = {
              Type = "oneshot";
              ExecStart = "${refresh}/bin/photon-refresh";
            };
          };
          timers.photon-refresh = {
            Unit.Description = "Semiannual Photon index rebuild";
            Timer = {
              OnCalendar = "*-01,07-01 04:00:00";
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };

      services.nginx.virtualHosts.${url} = {
        enableACME = true;
        forceSSL = true;
        locations."/".proxyPass = "http://127.0.0.1:2322";
      };
    };
}
