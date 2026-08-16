{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;

      # One stub for both the APIM gateway and the B2C auth endpoints, routed by
      # path and driven by a mode file the test flips between scenarios. Each
      # mode books a distinct sfid so the app's persistent ledger does not carry
      # one scenario's booking into the next. The class it serves lands on the
      # release-horizon day at 12:00 UTC, matching the test's schedule.
      stub = pkgs.writeText "aqua-stub.py" ''
        import http.server
        import json
        from datetime import datetime, timedelta, timezone

        STATE = "/var/lib/aqua-stub"
        MODE_FILE = STATE + "/mode"
        COUNT_FILE = STATE + "/bookings-count"
        ITEMS_FILE = STATE + "/items-count"


        def mode():
            try:
                with open(MODE_FILE) as handle:
                    return handle.read().strip() or "missing"
            except FileNotFoundError:
                return "missing"


        def target_day():
            # Matches the test's releaseHorizonDays = 1.
            return (datetime.now(timezone.utc) + timedelta(days=1)).date().isoformat()


        def item(sfid, is_full=False, my_booking=None):
            return {
                "sfid": sfid,
                "title": "Aqua Aerobics",
                "from_date": f"{target_day()}T12:00:00+00:00",
                "to_date": f"{target_day()}T13:00:00+00:00",
                "is_full": is_full,
                "members_on_waiting_list": 5 if is_full else 0,
                "my_booking": my_booking,
            }


        def items_for(current):
            if current == "book":
                return [item("S1")]
            if current == "waitlist":
                return [item("S2", is_full=True)]
            if current == "preexisting":
                return [item("S3", my_booking={"waitlist_position": None})]
            return []


        def read(counter_file):
            try:
                with open(counter_file) as handle:
                    return int(handle.read().strip() or "0")
            except (FileNotFoundError, ValueError):
                return 0


        def bump(counter_file):
            # Read before the "w" open — opening for write truncates the file first.
            current = read(counter_file)
            with open(counter_file, "w") as handle:
                handle.write(str(current + 1))


        class Handler(http.server.BaseHTTPRequestHandler):
            def _json(self, code, payload):
                body = json.dumps(payload).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if "/oauth2/v2.0/authorize" in self.path:
                    html = (
                        '<html><script>var SETTINGS = {"csrf":"TESTCSRF",'
                        '"transId":"TESTTX","api":"CombinedSigninAndSignup"};'
                        "</script></html>"
                    ).encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html")
                    self.send_header("Content-Length", str(len(html)))
                    self.end_headers()
                    self.wfile.write(html)
                    return
                if "/CombinedSigninAndSignup/confirmed" in self.path:
                    self.send_response(302)
                    self.send_header(
                        "Location",
                        "https://nh-booking-microsite.nuffieldhealth.com/auth/callback/"
                        "?code=TESTCODE&state=xyz",
                    )
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if "bookable_items" in self.path:
                    bump(ITEMS_FILE)
                    current = mode()
                    if current == "error":
                        self._json(500, {"error": "boom"})
                        return
                    if current == "recover":
                        # After a POST has landed (even though its response 503'd),
                        # the class comes back showing my_booking set.
                        landed = read(COUNT_FILE) >= 1
                        items = [item("S4", my_booking={"waitlist_position": None} if landed else None)]
                    else:
                        items = items_for(current)
                    self._json(200, {"class_available_time": "7:00", "items": items})
                    return
                self._json(404, {"path": self.path})

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                if "/oauth2/v2.0/token" in self.path:
                    self._json(
                        200,
                        {
                            "access_token": "TESTACCESS",
                            "refresh_token": "TESTREFRESH",
                            "token_type": "Bearer",
                            "expires_in": 3600,
                        },
                    )
                    return
                if "SelfAsserted" in self.path:
                    self._json(200, {"status": "200"})
                    return
                if "bookings" in self.path:
                    bump(COUNT_FILE)
                    current = mode()
                    if current == "recover":
                        # The reservation is taken server-side, but the response is lost.
                        self._json(503, {"error": "overloaded"})
                        return
                    if current == "waitlist":
                        self._json(200, {"my_booking": {"waitlist_position": 3}})
                    else:
                        self._json(200, {"my_booking": {"waitlist_position": None}})
                    return
                self._json(404, {"path": self.path})

            def log_message(self, *args):
                pass


        http.server.HTTPServer(("127.0.0.1", 9090), Handler).serve_forever()
      '';

      creds = pkgs.writeText "aqua-creds" ''
        NUFFIELD_USERNAME=test@example.com
        NUFFIELD_PASSWORD=test-password
      '';
    in
    {
      checks.aqua-booking = pkgs.testers.runNixOSTest {
        name = "aqua-booking";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.aqua-booking
          ];

          blizzard.aqua-booking = {
            credentialsFile = creds;
            apiBase = "http://127.0.0.1:9090/booking/";
            authInstance = "http://127.0.0.1:9090/";
            timezone = "UTC";
            releaseHorizonDays = 1;
            # Tiny budget so the retry loop exercises quickly instead of the 90s default.
            retry = {
              budgetSeconds = 3;
              baseSeconds = 0.2;
              maxBackoffSeconds = 0.5;
              maxRetryAfterSeconds = 1;
            };
            schedule = {
              monday = "12:00";
              tuesday = "12:00";
              wednesday = "12:00";
              thursday = "12:00";
              friday = "12:00";
              saturday = "12:00";
              sunday = "12:00";
            };
          };

          systemd.services.aqua-stub = {
            description = "Stub Nuffield APIM + B2C endpoints";
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStart = "${pkgs.python3}/bin/python3 ${stub}";
              StateDirectory = "aqua-stub";
            };
          };
        };

        testScript = alertHelpers + ''
          def set_mode(mode):
              machine.succeed(f"echo {mode} > /var/lib/aqua-stub/mode")


          def bookings_count():
              return int(
                  machine.succeed(
                      "cat /var/lib/aqua-stub/bookings-count 2>/dev/null || echo 0"
                  ).strip()
              )


          def items_count():
              return int(
                  machine.succeed(
                      "cat /var/lib/aqua-stub/items-count 2>/dev/null || echo 0"
                  ).strip()
              )


          def success_posts():
              return [post for post in posts() if post["topic"] == "test-notification"]


          def error_posts():
              return [post for post in posts() if post["topic"] == "blizzard-test"]


          def wait_for_success(count, timeout=30):
              deadline = time.time() + timeout
              while time.time() < deadline:
                  if len(success_posts()) >= count:
                      return success_posts()
                  time.sleep(0.5)
              raise Exception(f"expected {count} success posts, got {len(success_posts())}")


          start_recorder()
          machine.wait_for_unit("aqua-stub.service")
          machine.wait_for_open_port(9090)
          # Drive runs by hand; the real 07:00 timer must not fire mid-test.
          machine.succeed("systemctl stop aqua-booking.timer")

          with subtest("scripted login books a free seat and notifies the success topic"):
              set_mode("book")
              machine.succeed("rm -f /var/lib/aqua-booking/refresh_token")
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(1)[0]
              assert post["title"] == "machine: Aqua Aerobics booked", post
              assert "confirmed seat" in post["message"], post
              assert post["priority"] == 4, post
              # The login exchange must have persisted a rolling refresh token.
              machine.succeed("test -s /var/lib/aqua-booking/refresh_token")
              assert bookings_count() == 1, bookings_count()

          with subtest("a cancelled booking is a durable override — never rebooked"):
              before = len(success_posts())
              count_before = bookings_count()
              # Still looks bookable (user cancelled), but the ledger blocks it.
              machine.succeed("systemctl start aqua-booking.service")
              machine.wait_until_succeeds(
                  "journalctl --sync; journalctl -u aqua-booking.service -o cat"
                  " | grep -q 'not rebooking'"
              )
              time.sleep(1)
              assert len(success_posts()) == before, success_posts()
              assert bookings_count() == count_before, bookings_count()

          with subtest("a full class joins the waitlist and reports the position"):
              set_mode("waitlist")
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(2)[1]
              assert post["title"] == "machine: Aqua Aerobics waitlisted", post
              assert "#3" in post["message"], post

          with subtest("a missing class posts a low-priority schedule-change note"):
              set_mode("missing")
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(3)[2]
              assert post["title"] == "machine: Aqua Aerobics: nothing to book", post
              assert post["priority"] == 2, post
              assert post["tags"] == ["calendar"], post

          with subtest("a lost-response booking is recovered on retry, never double-booked"):
              set_mode("recover")
              machine.succeed("rm -f /var/lib/aqua-stub/bookings-count")
              before = len(success_posts())
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(before + 1)[before]
              assert post["title"] == "machine: Aqua Aerobics booked", post
              assert "recovered after a retry" in post["message"], post
              # Exactly one POST reached the server; the retry re-checked, it did not re-POST.
              assert bookings_count() == 1, bookings_count()

          with subtest("a pre-existing booking is recorded, not rebooked or re-notified"):
              set_mode("preexisting")
              before = len(success_posts())
              count_before = bookings_count()
              machine.succeed("systemctl start aqua-booking.service")
              time.sleep(1)
              assert len(success_posts()) == before, success_posts()
              assert bookings_count() == count_before, bookings_count()

          with subtest("transient errors are retried under budget, then page the alert module"):
              set_mode("error")
              seen = len(error_posts())
              items_before = items_count()
              machine.fail("systemctl start aqua-booking.service")
              # The 3s budget must have driven more than one discovery attempt.
              assert items_count() - items_before >= 2, items_count() - items_before
              deadline = time.time() + 30
              while time.time() < deadline and len(error_posts()) <= seen:
                  time.sleep(0.5)
              errors = error_posts()
              assert len(errors) == seen + 1, errors
              assert errors[-1]["title"] == "machine: Unit failed", errors[-1]
              assert "aqua-booking" in errors[-1]["message"], errors[-1]
        '';
      };
    };
}
