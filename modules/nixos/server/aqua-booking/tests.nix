{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
      inherit (pkgs) lib;

      # One stub for both the APIM gateway and the B2C auth endpoints, routed by
      # path and driven by a mode file the test flips between scenarios. Each
      # mode books a distinct sfid so the app's persistent ledger does not carry
      # one scenario's booking into the next. The classes it serves land on the
      # release-horizon day, matching the test's schedule.
      stub = pkgs.writeText "aqua-stub.py" ''
        import http.server
        import json
        import urllib.parse
        from datetime import datetime, timedelta, timezone

        STATE = "/var/lib/aqua-stub"
        MODE_FILE = STATE + "/mode"
        COUNT_FILE = STATE + "/bookings-count"
        ITEMS_FILE = STATE + "/items-count"
        AUTH_FILE = STATE + "/authorize-count"


        def mode():
            try:
                with open(MODE_FILE) as handle:
                    return handle.read().strip() or "missing"
            except FileNotFoundError:
                return "missing"


        def target_day():
            # Matches the test's releaseHorizonDays = 1.
            return (datetime.now(timezone.utc) + timedelta(days=1)).date().isoformat()


        def item(sfid, is_full=False, my_booking=None, title="Aqua Aerobics", hour=12):
            return {
                "sfid": sfid,
                "title": title,
                "from_date": f"{target_day()}T{hour:02d}:00:00+00:00",
                "to_date": f"{target_day()}T{hour + 1:02d}:00:00+00:00",
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
                return [item("S3", my_booking={"status": "Booked", "waitlist_position": None})]
            if current == "multi":
                return [item("S5"), item("S6", title="Yoga", hour=18)]
            if current == "partial":
                # The morning class never shows up; the evening one is there at once.
                return [item("S7", title="Yoga", hour=18)]
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
                    bump(AUTH_FILE)
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
                    # Implicit flow: the token comes back in the fragment, not a code.
                    self.send_header(
                        "Location",
                        "https://nh-booking-microsite.nuffieldhealth.com/auth/callback/"
                        "#access_token=TESTACCESS&token_type=Bearer&expires_in=3600"
                        "&state=xyz",
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
                        items = [item("S4", my_booking={"status": "Booked", "waitlist_position": None} if landed else None)]
                    else:
                        items = items_for(current)
                    self._json(200, {"class_available_time": "7:00", "items": items})
                    return
                self._json(404, {"path": self.path})

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                if "SelfAsserted" in self.path:
                    # B2C answers 200, naming the first claim it wanted and did not get.
                    form = urllib.parse.parse_qs(body.decode())
                    missing = [f for f in ("Email", "password") if not form.get(f)]
                    if missing:
                        self._json(
                            200,
                            {"status": "400", "message": f"Missing required element [{missing[0]}]"},
                        )
                        return
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
                        self._json(200, {"my_booking": {"status": "Waitlist", "waitlist_position": 3}})
                    else:
                        # Production returns a position on confirmed bookings too.
                        self._json(200, {"my_booking": {"status": "Booked", "waitlist_position": 1}})
                    return
                self._json(404, {"path": self.path})

            def log_message(self, *args):
                pass


        http.server.HTTPServer(("127.0.0.1", 9090), Handler).serve_forever()
      '';

      weekdays = [
        "monday"
        "tuesday"
        "wednesday"
        "thursday"
        "friday"
        "saturday"
        "sunday"
      ];

      # Stands in for the agenix secret: the private half of the config. Every
      # weekday is the same, because the release horizon decides which one runs.
      secretsFor =
        name: entries:
        (pkgs.formats.json { }).generate "aqua-secrets-${name}.json" {
          username = "test@example.com";
          password = "test-password";
          facilityId = "a2T4J000001JJfnUAG";
          gymName = "Crawley";
          schedule = lib.genAttrs weekdays (_: entries);
        };

      # The one-class shorthand: a bare time, booking the default class.
      secretsFile = secretsFor "single" "12:00";

      # Two classes a day, the second naming a class of its own.
      multiSecretsFile = secretsFor "multi" [
        "12:00"
        {
          time = "18:00";
          className = "Yoga";
        }
      ];

      # Shared so the multi-class node cannot drift from the single-class one.
      node = secrets: {
        imports = [
          alertRecorder
          config.flake.modules.nixos.aqua-booking
        ];

        # A topic distinct from the alert topic, so the test can tell booking
        # outcomes apart from operational pages.
        environment.etc."aqua-topic".text = "NTFY_TOPIC=aqua-test";

        blizzard.aqua-booking = {
          secretsFile = secrets;
          successTopicFile = "/etc/aqua-topic";
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
    in
    {
      # Pure-logic cover for the bits the VM cannot reach cheaply: London/BST
      # matching, schedule parsing, ledger pruning, and the retry budget.
      checks.aqua-booking-unit =
        pkgs.runCommand "aqua-booking-unit"
          {
            nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.tzdata ])) ];
          }
          ''
            cp -r ${./src} src
            chmod -R +w src
            cd src
            python -m unittest discover -s tests -t . -v 2>&1 | tee "$out"
          '';

      checks.aqua-booking = pkgs.testers.runNixOSTest {
        name = "aqua-booking";

        nodes.machine = node secretsFile;
        nodes.multi = node multiSecretsFile;

        testScript = alertHelpers + ''
          def set_mode(mode, node=machine):
              node.succeed(f"echo {mode} > /var/lib/aqua-stub/mode")


          def counter(name, node=machine):
              return int(
                  node.succeed(f"cat /var/lib/aqua-stub/{name} 2>/dev/null || echo 0").strip()
              )


          def authorize_count():
              return counter("authorize-count")


          def bookings_count(node=machine):
              return counter("bookings-count", node)


          def items_count():
              return counter("items-count")


          def aqua_posts(node=machine):
              raw = node.succeed("cat /var/lib/fake-ntfy/posts.jsonl 2>/dev/null || true")
              return [json.loads(line) for line in raw.splitlines() if line.strip()]


          def success_posts(node=machine):
              return [post for post in aqua_posts(node) if post["topic"] == "aqua-test"]


          def error_posts():
              return [post for post in posts() if post["topic"] == "blizzard-test"]


          def wait_for_success(count, timeout=30, node=machine):
              deadline = time.time() + timeout
              while time.time() < deadline:
                  if len(success_posts(node)) >= count:
                      return success_posts(node)
                  time.sleep(0.5)
              raise Exception(
                  f"expected {count} success posts, got {len(success_posts(node))}"
              )


          def wait_for_error(count, timeout=30):
              deadline = time.time() + timeout
              while time.time() < deadline:
                  if len(error_posts()) >= count:
                      return error_posts()
                  time.sleep(0.5)
              raise Exception(f"expected {count} error posts, got {len(error_posts())}")


          def quiesce(node):
              """Drive runs by hand; the real timers must not fire mid-test. Both are
              Persistent=true, so stop the catch-up run and drop whatever it posted."""
              node.wait_for_unit("multi-user.target")
              node.wait_for_unit("fake-ntfy.service")
              node.wait_for_unit("aqua-stub.service")
              node.wait_for_open_port(8080)
              node.wait_for_open_port(9090)
              node.succeed("systemctl stop aqua-booking.timer aqua-booking-freshness.timer")
              node.succeed("systemctl stop aqua-booking.service")
              node.succeed(": > /var/lib/fake-ntfy/posts.jsonl")


          start_recorder()
          quiesce(machine)

          with subtest("the dry-run entrypoint reports the target without booking"):
              set_mode("book")
              out = machine.succeed("aqua-booking-dry-run")
              assert "would book a seat" in out, out
              assert "sfid=S1" in out, out
              # The raw item is the only way to debug a schema surprise after the fact.
              assert "raw item" in out, out
              # The exact titles on the day: what a new schedule entry has to name.
              assert "feed: 12:00 Aqua Aerobics" in out, out
              assert "is_full=False" in out, out
              # A dry run is read by a human: levels are visible, debug included.
              assert "INFO" in out, out
              assert "DEBUG" in out, out
              assert bookings_count() == 0, bookings_count()
              assert success_posts() == [], success_posts()
              # Discovery only: no ledger entry, and no heartbeat for the watchdog.
              machine.fail("test -e /var/lib/aqua-booking/booked.jsonl")
              machine.fail("test -e /var/lib/aqua-booking/last_run")
              dir_mode = machine.succeed("stat -c %a /var/lib/aqua-booking").strip()
              assert dir_mode == "700", dir_mode

          with subtest("the dry-run entrypoint reports a full class as a waitlist join"):
              set_mode("waitlist")
              out = machine.succeed("aqua-booking-dry-run")
              assert "FULL, would join waitlist" in out, out
              assert bookings_count() == 0, bookings_count()

          with subtest("the dry-run entrypoint leaves a pre-existing booking unrecorded"):
              # Recording one would be a durable override: a class the service then
              # refuses to rebook if it were cancelled.
              set_mode("preexisting")
              out = machine.succeed("aqua-booking-dry-run")
              assert "already booked outside this service" in out, out
              # Two dry runs have already happened: the output must not replay them.
              assert out.count("targets on ") == 1, out
              machine.fail("test -e /var/lib/aqua-booking/booked.jsonl")

          with subtest("scripted login books a free seat and notifies the success topic"):
              set_mode("book")
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(1)[0]
              assert post["title"] == "machine: Aqua Aerobics booked", post
              assert "confirmed seat" in post["message"], post
              # A position on a class with space is not a waitlist place.
              assert "#1" not in post["message"], post
              assert post["priority"] == 4, post
              machine.succeed(
                  "journalctl --sync; journalctl -u aqua-booking.service -o cat"
                  " | grep -q 'result: booked S1'"
              )
              # Implicit flow hands back no refresh token, so none is ever written.
              machine.fail("test -e /var/lib/aqua-booking/refresh_token")
              assert bookings_count() == 1, bookings_count()
              # The freshness watchdog reads this heartbeat.
              machine.succeed("test -s /var/lib/aqua-booking/last_run")

          with subtest("a cancelled booking is a durable override — never rebooked"):
              before = len(success_posts())
              count_before = bookings_count()
              auth_before = authorize_count()
              # Still looks bookable (user cancelled), but the ledger blocks it.
              machine.succeed("systemctl start aqua-booking.service")
              machine.wait_until_succeeds(
                  "journalctl --sync; journalctl -u aqua-booking.service -o cat"
                  " | grep -q 'not rebooking'"
              )
              time.sleep(1)
              assert len(success_posts()) == before, success_posts()
              assert bookings_count() == count_before, bookings_count()
              # Nothing to reuse without a refresh token: every run signs in afresh.
              assert authorize_count() == auth_before + 1, authorize_count()

          with subtest("a full class joins the waitlist and reports the position"):
              set_mode("waitlist")
              machine.succeed("systemctl start aqua-booking.service")
              post = wait_for_success(2)[1]
              assert post["title"] == "machine: Aqua Aerobics waitlisted", post
              assert "#3" in post["message"], post
              # journald must have parsed the <4> prefix into a real priority,
              # so `journalctl -p warning` surfaces the days that missed a seat.
              machine.succeed(
                  "journalctl --sync; journalctl -u aqua-booking.service -p warning -o cat"
                  " | grep -q 'result: waitlisted'"
              )

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

          with subtest("the freshness watchdog stays quiet after a recent run"):
              machine.succeed("touch /var/lib/aqua-booking/last_run")
              seen = len(error_posts())
              machine.succeed("systemctl start aqua-booking-freshness.service")
              time.sleep(1)
              assert len(error_posts()) == seen, error_posts()

          with subtest("a timer that never fired is caught by the watchdog"):
              seen = len(error_posts())
              machine.succeed("touch -d '3 days ago' /var/lib/aqua-booking/last_run")
              machine.succeed("systemctl start aqua-booking-freshness.service")
              errors = wait_for_error(seen + 1)
              assert errors[-1]["title"] == "machine: Gym booking stale", errors[-1]
              assert "72h" in errors[-1]["message"], errors[-1]

          with subtest("a service that has never completed a run is caught too"):
              seen = len(error_posts())
              machine.succeed("rm -f /var/lib/aqua-booking/last_run")
              machine.succeed("systemctl start aqua-booking-freshness.service")
              errors = wait_for_error(seen + 1)
              assert "never completed a run" in errors[-1]["message"], errors[-1]

          quiesce(multi)

          with subtest("a day of two different classes books both, in one sign-in"):
              set_mode("multi", multi)
              auth_before = counter("authorize-count", multi)
              multi.succeed("systemctl start aqua-booking.service")
              got = sorted(post["title"] for post in wait_for_success(2, node=multi))
              assert got == ["multi: Aqua Aerobics booked", "multi: Yoga booked"], got
              assert bookings_count(multi) == 2, bookings_count(multi)
              # One feed sweep resolved both, so both rode the same token.
              assert counter("authorize-count", multi) == auth_before + 1, counter(
                  "authorize-count", multi
              )
              ledger = multi.succeed("cat /var/lib/aqua-booking/booked.jsonl")
              assert '"sfid": "S5"' in ledger, ledger
              assert '"sfid": "S6"' in ledger, ledger

          with subtest("one class missing does not cost the other its seat"):
              set_mode("partial", multi)
              before = len(success_posts(multi))
              count_before = bookings_count(multi)
              multi.succeed("systemctl start aqua-booking.service")
              got = {
                  post["title"]: post for post in wait_for_success(before + 2, node=multi)[before:]
              }
              assert "multi: Yoga booked" in got, got
              # The morning class never appeared; only it gets the schedule-change note.
              note = got.get("multi: Aqua Aerobics: nothing to book")
              assert note is not None, got
              assert note["priority"] == 2, note
              # The evening class was booked once, on the first sweep, and the
              # retries for the missing one never went back over it.
              assert bookings_count(multi) == count_before + 1, bookings_count(multi)
              multi.succeed("test -s /var/lib/aqua-booking/last_run")
        '';
      };
    };
}
