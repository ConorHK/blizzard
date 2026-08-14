{ config, ... }:
{
  # Captures what would have gone to ntfy, so alerts can be asserted on by
  # content without egress or a secret.
  flake.testSupport = {
    alertRecorder =
      { pkgs, ... }:
      let
        server = pkgs.writeText "fake-ntfy.py" ''
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
        imports = [ config.flake.modules.nixos.alerts ];

        environment.systemPackages = [ pkgs.python3 ];
        environment.etc."alert-topic".text = "NTFY_TOPIC=blizzard-test";

        blizzard.alerts = {
          endpoint = "http://127.0.0.1:8080";
          topicFile = "/etc/alert-topic";
        };

        systemd.services.fake-ntfy = {
          description = "Record alerts that would go to ntfy";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${server}";
            StateDirectory = "fake-ntfy";
          };
        };
      };

    alertHelpers = ''
      import json
      import time


      def posts():
          raw = machine.succeed("cat /var/lib/fake-ntfy/posts.jsonl 2>/dev/null || true")
          return [json.loads(line) for line in raw.splitlines() if line.strip()]


      def wait_for_posts(count, timeout=30):
          """Alerts are delivered asynchronously; wait for at least `count`."""
          deadline = time.time() + timeout
          while time.time() < deadline:
              current = posts()
              if len(current) >= count:
                  return current
              time.sleep(0.5)
          raise Exception(f"expected {count} alerts, got {len(posts())}")


      def start_recorder():
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("fake-ntfy.service")
          machine.wait_for_open_port(8080)
    '';
  };
}
