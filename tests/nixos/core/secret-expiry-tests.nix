{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
      inherit (config.flake.modules.nixos) secret-expiry;

      # Token text picks the answer.
      fakeApis = pkgs.writeText "fake-apis.py" ''
        import http.server
        import json


        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                token = self.headers.get("Authorization", "").removeprefix("Bearer ")
                if self.path.startswith("/cachix/cache/"):
                    permission = "Write" if token.endswith(".write") else "Read"
                    self.reply(200, {}, json.dumps({"permission": permission}))
                elif self.path == "/github/rate_limit":
                    if token.startswith("bad"):
                        self.reply(401, {}, "{}")
                    elif token.startswith("good-"):
                        expiry = token.removeprefix("good-") + " 00:00:00 UTC"
                        self.reply(200, {"GitHub-Authentication-Token-Expiration": expiry}, "{}")
                    else:
                        self.reply(200, {}, "{}")
                else:
                    self.reply(404, {}, "{}")

            def reply(self, status, headers, body):
                self.send_response(status)
                for key, value in headers.items():
                    self.send_header(key, value)
                self.end_headers()
                self.wfile.write(body.encode())

            def log_message(self, *args):
                pass


        http.server.HTTPServer(("127.0.0.1", 8081), Handler).serve_forever()
      '';
    in
    {
      checks.secret-expiry = pkgs.testers.runNixOSTest {
        name = "secret-expiry";

        nodes.machine =
          { config, ... }:
          {
            imports = [
              alertRecorder
              secret-expiry
            ];

            blizzard.secretExpiry.secrets = {
              cachix = {
                file = "/run/secrets/cachix";
                probe = config.blizzard.secretExpiry.probes.cachix "conorhk";
              };
              github = {
                file = "/run/secrets/github";
                probe = config.blizzard.secretExpiry.probes.github;
              };
              manual.file = "/run/secrets/manual";
              forever = {
                file = "/run/secrets/manual";
                expires = "never";
              };
            };

            systemd = {
              # Only the test starts checks.
              timers.secret-expiry.wantedBy = pkgs.lib.mkForce [ ];

              services.secret-expiry.environment = {
                CACHIX_API = "http://127.0.0.1:8081/cachix";
                GITHUB_API = "http://127.0.0.1:8081/github";
              };

              services.fake-apis = {
                description = "Answer cachix and GitHub lookups";
                wantedBy = [ "multi-user.target" ];
                serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 ${fakeApis}";
              };
            };
          };

        testScript = alertHelpers + ''
          import base64
          import shlex

          DAY = 86400


          def b64(data):
              return base64.urlsafe_b64encode(data.encode()).decode().rstrip("=")


          def jwt(signature, exp=None):
              claims = {"jti": "test"} if exp is None else {"jti": "test", "exp": exp}
              return f"{b64('{}')}.{b64(json.dumps(claims))}.{signature}"


          def now():
              return int(machine.succeed("date +%s"))


          def day(offset):
              return machine.succeed(f"date -u -d '+{offset} days' +%F").strip()


          def secrets(cachix, github):
              machine.succeed(
                  "mkdir -p /run/secrets",
                  f"printf %s {shlex.quote(cachix)} > /run/secrets/cachix",
                  f"printf 'access-tokens = github.com=%s\\n' {shlex.quote(github)} > /run/secrets/github",
                  "touch /run/secrets/manual",
              )


          def run():
              seen = len(posts())
              machine.succeed("systemctl start secret-expiry.service")
              machine.succeed("alert-drain")
              return {a["title"].removeprefix("machine: "): a for a in posts()[seen:]}


          start_recorder()
          machine.wait_for_unit("fake-apis.service")
          machine.wait_for_open_port(8081)

          with subtest("healthy probes stay quiet, a dateless secret asks for one"):
              secrets(jwt("write", now() + 60 * DAY), f"good-{day(60)}")
              alerts = run()
              assert set(alerts) == {"manual secret"}, alerts
              assert alerts["manual secret"]["message"] == (
                  "Expiry unknown. Set blizzard.secretExpiry.secrets.manual.expires."
              ), alerts

          with subtest("expiry dates from both probes warn inside the window"):
              secrets(jwt("write", now() + 5 * DAY + 3600), f"good-{day(6)}")
              alerts = run()
              assert alerts["cachix secret"]["message"].startswith("Expires in 5 days"), alerts
              assert alerts["cachix secret"]["priority"] == 3, alerts
              assert alerts["github secret"]["message"].startswith("Expires in "), alerts

          with subtest("rejected credentials page urgently with the reason"):
              secrets(jwt("read", now() - DAY), "bad")
              alerts = run()
              cachix = alerts["cachix secret"]
              assert cachix["message"] == "Cannot push to conorhk: permission Read.", alerts
              assert cachix["priority"] == 4, alerts
              assert alerts["github secret"]["message"] == "GitHub rejects the token.", alerts
              assert alerts["github secret"]["priority"] == 4, alerts

          with subtest("a token without an expiry header falls back to the date"):
              secrets(jwt("write", now() + 60 * DAY), "plain")
              alerts = run()
              assert alerts["github secret"]["message"].startswith("Expiry unknown."), alerts

          with subtest("an unreachable api fails the unit, which pages"):
              secrets(jwt("write", now() + 60 * DAY), f"good-{day(60)}")
              seen = len(posts())
              machine.succeed("systemctl stop fake-apis.service")
              machine.fail("systemctl start secret-expiry.service")
              titles = [a["title"] for a in wait_for_posts(seen + 2)[seen:]]
              assert "machine: Unit failed" in titles, titles
        '';
      };
    };
}
