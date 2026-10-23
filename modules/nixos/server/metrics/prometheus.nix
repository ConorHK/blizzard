{ config, ... }:
let
  addresses = config.flake.tailnetAddresses;
in
{
  flake.modules.nixos.prometheus =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.metrics;
      exporters = config.blizzard.metricsExporters;

      bridge = pkgs.writers.writePython3Bin "alertmanager-ntfy" { } ''
        import http.server
        import json
        import os
        import subprocess

        PORT = int(os.environ["BRIDGE_PORT"])


        def send(host, alerts, status):
            first = alerts[0]
            title = first["annotations"].get("summary") or (
                first["labels"]["alertname"]
            )
            lines = [a["annotations"].get("description", "") for a in alerts]
            if len(alerts) > 1:
                title = f"{title} x{len(alerts)}"
            priority, tag = "4", "warning"
            if status == "resolved":
                title = f"{title} resolved"
                priority, tag = "3", "white_check_mark"
            subprocess.run(
                ["alert-send", title, "\n".join(lines) or title, priority, tag],
                env={**os.environ, "ALERT_HOST": host},
            )


        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                try:
                    alerts = json.loads(body)["alerts"]
                except (ValueError, KeyError):
                    self.send_response(400)
                    self.end_headers()
                    return
                # alert-send spools, so answer before it tries ntfy.
                self.send_response(200)
                self.end_headers()
                batches = {}
                for alert in alerts:
                    host = alert["labels"].get("host", "metrics")
                    key = (host, alert["status"])
                    batches.setdefault(key, []).append(alert)
                for (host, status), batch in sorted(batches.items()):
                    send(host, batch, status)

            def log_message(self, *args):
                pass


        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
        server.serve_forever()
      '';
    in
    {
      options.blizzard.metrics = {
        targets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = addresses;
          description = "Hosts to scrape, by hostname.";
        };

        bridgePort = lib.mkOption {
          type = lib.types.port;
          default = 9095;
        };
      };

      config = {
        services.prometheus = {
          enable = true;
          listenAddress = "127.0.0.1";
          port = 9090;
          retentionTime = "30d";
          globalConfig = {
            scrape_interval = "30s";
            evaluation_interval = "30s";
          };
          ruleFiles = [ ./rules.yml ];
          scrapeConfigs =
            lib.mapAttrsToList
              (job: port: {
                job_name = job;
                static_configs = lib.mapAttrsToList (host: address: {
                  targets = [ "${address}:${toString port}" ];
                  labels = { inherit host; };
                }) cfg.targets;
              })
              {
                node = exporters.nodePort;
                cadvisor = exporters.cadvisorPort;
              };
          alertmanagers = [
            {
              static_configs = [
                { targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ]; }
              ];
            }
          ];

          alertmanager = {
            enable = true;
            listenAddress = "127.0.0.1";
            # A lone instance needs no gossip port.
            extraFlags = [ "--cluster.listen-address=" ];
            configuration = {
              route = {
                receiver = "ntfy";
                group_by = [
                  "alertname"
                  "host"
                ];
                group_wait = "30s";
                group_interval = "5m";
                repeat_interval = "24h";
              };
              receivers = [
                {
                  name = "ntfy";
                  webhook_configs = [ { url = "http://127.0.0.1:${toString cfg.bridgePort}/"; } ];
                }
              ];
            };
          };
        };

        systemd.services = {
          prometheus.unitConfig.OnFailure = "alert-failure@prometheus.service";
          alertmanager.unitConfig.OnFailure = "alert-failure@alertmanager.service";

          alertmanager-ntfy = {
            description = "Forward alertmanager alerts to ntfy";
            wantedBy = [ "multi-user.target" ];
            before = [ "alertmanager.service" ];
            path = [ config.blizzard.alerts.send ];
            environment.BRIDGE_PORT = toString cfg.bridgePort;
            unitConfig.OnFailure = "alert-failure@alertmanager-ntfy.service";
            serviceConfig = {
              ExecStart = lib.getExe bridge;
              Restart = "on-failure";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
            };
          };
        };
      };
    };
}
