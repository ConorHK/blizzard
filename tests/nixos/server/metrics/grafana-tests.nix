{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder;
      secret = text: {
        inherit text;
        user = "grafana";
        mode = "0400";
      };
    in
    {
      checks.grafana = pkgs.testers.runNixOSTest {
        name = "grafana";

        nodes.machine = {
          imports = with config.flake.modules.nixos; [
            alertRecorder
            disk-alerts
            grafana
            metrics-exporters
            prometheus
          ];

          virtualisation.memorySize = 2048;
          environment = {
            systemPackages = [
              pkgs.curl
              pkgs.jq
            ];
            etc = {
              grafana-key = secret "test-secret-key";
              grafana-password = secret "test-password";
            };
          };

          blizzard = {
            metricsExporters.address = "127.0.0.1";
            metrics.targets.machine = "127.0.0.1";
            grafana = {
              secretKeyFile = "/etc/grafana-key";
              adminPasswordFile = "/etc/grafana-password";
            };
          };
        };

        testScript = ''
          import json
          import shlex

          api = "http://127.0.0.1:3005/api"


          def code(args):
              return machine.succeed(
                  f"curl -s -o /dev/null -w '%{{http_code}}' {args}"
              ).strip()


          machine.wait_for_unit("grafana.service")
          machine.wait_for_unit("prometheus.service")
          machine.wait_until_succeeds(f"curl -sf {api}/health", timeout=120)

          with subtest("anonymous viewers see the dashboard"):
              assert code(f"{api}/dashboards/uid/blizzard-overview") == "200"

          with subtest("anonymous viewers cannot edit"):
              assert code(
                  f"-X POST -H 'Content-Type: application/json' "
                  f"-d '{{\"dashboard\": {{\"title\": \"x\"}}}}' {api}/dashboards/db"
              ) == "403"

          with subtest("the admin password logs in"):
              assert code(f"-u admin:test-password {api}/user") == "200"
              assert code(f"-u admin:wrong {api}/user") == "401"

          with subtest("every panel query runs against prometheus"):
              machine.wait_until_succeeds(
                  "curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up' | "
                  "jq -e '.data.result | length > 0'",
                  timeout=120,
              )
              dashboard = json.loads(
                  machine.succeed(f"curl -sf {api}/dashboards/uid/blizzard-overview")
              )["dashboard"]
              exprs = [t["expr"] for p in dashboard["panels"] for t in p["targets"]]
              assert len(exprs) > 8, exprs
              for expr in exprs:
                  expr = expr.replace("$__rate_interval", "1m").replace("$host", ".*")
                  machine.succeed(
                      "curl -sf -G http://127.0.0.1:9090/api/v1/query "
                      f"--data-urlencode {shlex.quote('query=' + expr)}"
                  )

          with subtest("grafana reaches prometheus"):
              machine.succeed(
                  f"curl -sf -u admin:test-password {api}/datasources/uid/prometheus/health"
              )
        '';
      };
    };
}
