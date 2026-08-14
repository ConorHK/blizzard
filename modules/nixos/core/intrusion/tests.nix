{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.tripwire = pkgs.testers.runNixOSTest {
        name = "tripwire";

        nodes.machine =
          { pkgs, ... }:
          let
            recorder = pkgs.writeText "fake-ntfy.py" ''
              import http.server
              import json

              LOG = "/var/lib/fake-ntfy/posts.jsonl"


              class Handler(http.server.BaseHTTPRequestHandler):
                  def do_POST(self):
                      body = self.rfile.read(int(self.headers["Content-Length"]))
                      with open(LOG, "a") as log:
                          json.dump(json.loads(body), log)
                          log.write("\n")
                      self.send_response(200)
                      self.end_headers()

                  def log_message(self, *args):
                      pass


              http.server.HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
            '';
          in
          {
            imports = with config.flake.modules.nixos; [
              alerts
              tripwire
            ];

            environment.systemPackages = [ pkgs.python3 ];
            environment.etc."alert-topic".text = "NTFY_TOPIC=tripwire-test";

            blizzard = {
              alerts = {
                endpoint = "http://127.0.0.1:8080";
                topicFile = "/etc/alert-topic";
              };
              tripwire.scanRoots = [ "/var/scan" ];
            };

            systemd.services.fake-ntfy = {
              description = "Record alerts that would go to ntfy";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.python3}/bin/python3 ${recorder}";
                StateDirectory = "fake-ntfy";
              };
            };
          };

        testScript = ''
          import json


          def posts():
              raw = machine.succeed("cat /var/lib/fake-ntfy/posts.jsonl 2>/dev/null || true")
              return [json.loads(line) for line in raw.splitlines() if line.strip()]


          def status(mode):
              machine.succeed("journalctl --sync")
              out = machine.succeed(
                  f"journalctl -u tripwire-{mode}.service -o cat | grep '^tripwire' || true"
              )
              return out.splitlines()


          def run(mode):
              """Start one check, return only the status lines and alerts it produced."""
              seen_status = len(status(mode))
              seen_posts = len(posts())
              machine.succeed(f"systemctl start tripwire-{mode}.service")
              return status(mode)[seen_status:], posts()[seen_posts:]


          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("fake-ntfy.service")
          machine.wait_for_open_port(8080)
          machine.succeed("mkdir -p /var/scan")

          with subtest("first run records a baseline and stays quiet"):
              lines, alerts = run("fast")
              assert "baseline created" in lines[0], lines
              assert alerts == [], alerts

          with subtest("an untouched system reports no drift"):
              lines, alerts = run("fast")
              assert "no drift" in lines[0], lines
              assert alerts == [], alerts

          with subtest("a new setuid binary alerts once, with the offending line"):
              machine.succeed("touch /var/scan/backdoor && chmod 4755 /var/scan/backdoor")
              lines, alerts = run("fast")
              assert len(alerts) == 1, alerts
              assert alerts[0]["title"] == "machine: System drift detected (fast)", alerts[0]
              assert alerts[0]["priority"] == 4, alerts[0]
              assert alerts[0]["tags"] == ["rotating_light"], alerts[0]
              assert "+setuid: /var/scan/backdoor" in alerts[0]["message"], alerts[0]

          with subtest("drift is re-baselined so it does not alert again"):
              lines, alerts = run("fast")
              assert "no drift" in lines[0], lines
              assert alerts == [], alerts

          with subtest("a new account is drift"):
              machine.succeed("useradd -M intruder")
              lines, alerts = run("fast")
              assert len(alerts) == 1, alerts
              assert "intruder" in alerts[0]["message"], alerts[0]

          with subtest("full mode baselines and holds steady"):
              lines, alerts = run("full")
              assert "baseline created" in lines[0], lines
              assert alerts == [], alerts
              lines, alerts = run("full")
              assert "no drift" in lines[0], lines
              assert alerts == [], alerts

          with subtest("a new listener is drift for full only"):
              machine.succeed(
                  "systemd-run --unit=drift-listener "
                  "$(command -v python3) -m http.server 9000 --bind 0.0.0.0"
              )
              machine.wait_for_open_port(9000)

              lines, alerts = run("fast")
              assert "no drift" in lines[0], lines
              assert alerts == [], alerts

              lines, alerts = run("full")
              assert len(alerts) == 1, alerts
              assert alerts[0]["title"] == "machine: System drift detected (full)", alerts[0]
              assert "+listener:" in alerts[0]["message"], alerts[0]
              assert "9000" in alerts[0]["message"], alerts[0]

          with subtest("an unknown mode exits 2"):
              exec_start = machine.succeed(
                  "systemctl show -p ExecStart --value tripwire-fast.service"
              )
              tripwire = exec_start.split("path=")[1].split()[0]
              rc, _ = machine.execute(f"{tripwire} bogus")
              assert rc == 2, rc
        '';
      };
    };
}
