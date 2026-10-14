{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;

      fakeGatus = pkgs.writeText "fake-gatus.py" ''
        import http.server


        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200 if self.path == "/health" else 404)
                self.end_headers()

            def log_message(self, *args):
                pass


        http.server.HTTPServer(("127.0.0.1", 8090), Handler).serve_forever()
      '';
    in
    {
      checks.gatus-watch = pkgs.testers.runNixOSTest {
        name = "gatus-watch";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.gatus-watch
          ];

          blizzard.gatusWatch.url = "http://127.0.0.1:8090/health";
          # Only the test starts probes.
          systemd.timers.gatus-watch.wantedBy = pkgs.lib.mkForce [ ];

          systemd.services.fake-gatus = {
            description = "Answer gatus health probes";
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${fakeGatus}";
          };
        };

        testScript = alertHelpers + ''
          def probe():
              machine.succeed("systemctl start gatus-watch.service")


          start_recorder()
          machine.wait_for_unit("fake-gatus.service")
          machine.wait_for_open_port(8090)

          with subtest("a healthy monitor stays quiet"):
              probe()
              assert posts() == [], posts()

          with subtest("short outages ride through"):
              machine.succeed("systemctl stop fake-gatus.service")
              probe()
              probe()
              assert posts() == [], posts()

          with subtest("the third miss pages once"):
              probe()
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Monitor down", alert
              assert alert["priority"] == 4, alert
              probe()
              assert len(posts()) == 1, posts()

          with subtest("recovery is reported"):
              machine.succeed("systemctl start fake-gatus.service")
              machine.wait_for_open_port(8090)
              probe()
              alert = wait_for_posts(2)[1]
              assert alert["title"] == "machine: Monitor back", alert
              probe()
              assert len(posts()) == 2, posts()
        '';
      };
    };
}
