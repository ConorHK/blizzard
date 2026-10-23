{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.prometheus = pkgs.testers.runNixOSTest {
        name = "prometheus";

        nodes.machine = {
          imports = with config.flake.modules.nixos; [
            alertRecorder
            disk-alerts
            metrics-exporters
            prometheus
          ];

          virtualisation.memorySize = 2048;
          environment.systemPackages = [
            pkgs.curl
            pkgs.jq
          ];

          blizzard = {
            metricsExporters.address = "127.0.0.1";
            metrics.targets.machine = "127.0.0.1";
          };

          services.prometheus.rules = [
            (builtins.toJSON {
              groups = [
                {
                  name = "canary";
                  rules = [
                    {
                      alert = "Canary";
                      expr = "vector(1)";
                      labels.host = "puca";
                      annotations = {
                        summary = "Canary";
                        description = "always firing";
                      };
                    }
                  ];
                }
              ];
            })
          ];
        };

        testScript = alertHelpers + ''
          def bridge(payload):
              return machine.succeed(
                  "curl -sS -o /dev/null -w '%{http_code}' "
                  f"--data-binary '{json.dumps(payload)}' http://127.0.0.1:9095/"
              ).strip()


          def alert(status, description):
              return {
                  "status": status,
                  "labels": {"alertname": "DiskFull", "host": "leprechaun"},
                  "annotations": {"summary": "Disk full", "description": description},
              }


          start_recorder()
          for unit in ["prometheus", "alertmanager", "alertmanager-ntfy", "cadvisor"]:
              machine.wait_for_unit(f"{unit}.service")

          with subtest("both exporters are scraped"):
              machine.wait_until_succeeds(
                  "curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up' | "
                  "jq -e '[.data.result[] | select(.value[1] == \"1\")] | length == 2'",
                  timeout=120,
              )

          with subtest("a firing rule reaches ntfy under its host"):
              [canary] = wait_for_posts(1, timeout=180)
              assert canary["title"] == "puca: Canary", canary
              assert canary["message"] == "always firing", canary
              assert canary["topic"] == "blizzard-test", canary

          with subtest("a group sends one message"):
              assert bridge({"alerts": [alert("resolved", "/a"), alert("resolved", "/b")]}) == "200"
              batch = wait_for_posts(2)[1]
              assert batch["title"] == "leprechaun: Disk full x2 resolved", batch
              assert batch["message"] == "/a\n/b", batch
              assert "white_check_mark" in batch["tags"], batch

          with subtest("garbage is rejected"):
              assert bridge({"nope": 1}) == "400"
        '';
      };
    };
}
