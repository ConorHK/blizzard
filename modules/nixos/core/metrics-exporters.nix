{ config, ... }:
let
  addresses = config.flake.tailnetAddresses;
in
{
  flake.modules.nixos.metrics-exporters =
    { config, lib, ... }:
    let
      cfg = config.blizzard.metricsExporters;
    in
    {
      options.blizzard.metricsExporters = {
        address = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = addresses.${config.networking.hostName} or null;
          description = "Address the exporters bind to; null disables them.";
        };

        nodePort = lib.mkOption {
          type = lib.types.port;
          default = 9100;
        };

        cadvisorPort = lib.mkOption {
          type = lib.types.port;
          default = 9101;
        };
      };

      config = lib.mkIf (cfg.address != null) {
        # Bind before tailscale assigns the address.
        boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = lib.mkDefault 1;

        services = {
          prometheus.exporters.node = {
            enable = true;
            listenAddress = cfg.address;
            port = cfg.nodePort;
            enabledCollectors = [ "systemd" ];
          };

          cadvisor = {
            enable = true;
            listenAddress = cfg.address;
            port = cfg.cadvisorPort;
            extraOptions = [
              "-enable_metrics=cpu,memory,oom_event,pressure"
              "-housekeeping_interval=30s"
              "-store_container_labels=false"
            ];
          };
        };

        # Its readiness probe spins until tailscale is up.
        systemd.services.cadvisor.postStart = lib.mkForce "";

        # Prometheus pages instead, so one rule covers every host.
        blizzard.diskAlerts.page = false;
      };
    };
}
