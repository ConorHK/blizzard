{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;

      # Tokens signed "write" can push.
      fakeCachix = pkgs.writeText "fake-cachix.py" ''
        import http.server
        import json


        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                token = self.headers.get("Authorization", "").removeprefix("Bearer ")
                body = json.dumps({
                    "name": self.path.rsplit("/", 1)[-1],
                    "permission": "Write" if token.endswith(".write") else "Read",
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass


        http.server.HTTPServer(("127.0.0.1", 8081), Handler).serve_forever()
      '';
    in
    {
      checks.cachix-token-check = pkgs.testers.runNixOSTest {
        name = "cachix-token-check";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.cachix-token-check
          ];

          blizzard.cachixTokenCheck = {
            tokenFile = "/run/cachix-token";
            cache = "conorhk";
          };

          systemd.services.cachix-token-check.environment.CACHIX_API = "http://127.0.0.1:8081/api/v1";

          systemd.services.fake-cachix = {
            description = "Answer cachix cache lookups";
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${fakeCachix}";
          };
        };

        testScript = alertHelpers + ''
          import base64
          import shlex

          DAY = 86400
          API = "CACHIX_API=http://127.0.0.1:8081/api/v1"


          def b64(data):
              return base64.urlsafe_b64encode(data.encode()).decode().rstrip("=")


          def token(signature, exp=None):
              claims = {"jti": "test"} if exp is None else {"jti": "test", "exp": exp}
              return f"{b64('{}')}.{b64(json.dumps(claims))}.{signature}"


          def now():
              return int(machine.succeed("date +%s"))


          def check(tok, expires=""):
              machine.succeed(f"printf %s {shlex.quote(tok)} > /run/cachix-token")
              return machine.succeed(
                  f"{API} cachix-token-check /run/cachix-token conorhk {shlex.quote(expires)} 14"
              )


          def alerts_after(seen, run):
              run()
              machine.succeed("alert-drain")
              return posts()[seen:]


          start_recorder()
          machine.wait_for_unit("fake-cachix.service")
          machine.wait_for_open_port(8081)

          with subtest("a healthy token stays quiet"):
              seen = len(posts())
              new = alerts_after(seen, lambda: check(token("write", now() + 60 * DAY)))
              assert new == [], new

          with subtest("an exp claim inside the window warns"):
              seen = len(posts())
              new = alerts_after(seen, lambda: check(token("write", now() + 5 * DAY + 3600)))
              assert len(new) == 1, new
              assert new[0]["title"] == "machine: Cachix token", new
              assert new[0]["message"].startswith("Expires in 5 days, on "), new
              assert new[0]["priority"] == 3, new

          with subtest("an expired token that cannot push is one urgent alert"):
              seen = len(posts())
              new = alerts_after(seen, lambda: check(token("read", now() - DAY)))
              assert len(new) == 1, new
              assert "Expired on " in new[0]["message"], new
              assert "Cannot push to conorhk: permission Read." in new[0]["message"], new
              assert new[0]["priority"] == 4, new

          with subtest("the declared date stands in for a missing claim"):
              seen = len(posts())
              soon = machine.succeed("date -u -d '+2 days' +%F").strip()
              new = alerts_after(seen, lambda: check(token("write"), soon))
              assert len(new) == 1, new
              assert new[0]["message"] == f"Expires in 1 day, on {soon}.", new
              assert new[0]["priority"] == 4, new

          with subtest("no claim and no date asks for one"):
              seen = len(posts())
              new = alerts_after(seen, lambda: check(token("write")))
              assert len(new) == 1, new
              assert new[0]["message"] == "Expiry unknown. Set blizzard.cachixTokenCheck.expires.", new

          with subtest("never skips the date check"):
              seen = len(posts())
              new = alerts_after(seen, lambda: check(token("write"), "never"))
              assert new == [], new

          with subtest("the unit runs sandboxed and reports an unreachable api"):
              machine.succeed(f"printf %s {shlex.quote(token('write', now() + 60 * DAY))} > /run/cachix-token")
              machine.succeed("systemctl start cachix-token-check.service")
              seen = len(posts())
              machine.succeed("systemctl stop fake-cachix.service")
              machine.fail("systemctl start cachix-token-check.service")
              alert = wait_for_posts(seen + 1)[seen]
              assert alert["title"] == "machine: Unit failed", alert
              assert "cachix-token-check" in alert["message"], alert
        '';
      };
    };
}
