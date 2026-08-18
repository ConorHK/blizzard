{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;

      # Sessions logind never opened, written straight to the journal socket so
      # suppression and throttling can be driven without staging a real login.
      emitSession = pkgs.writers.writePython3Bin "emit-session" { flakeIgnore = [ "E501" ]; } ''
        import socket
        import sys

        user, session_id = sys.argv[1], sys.argv[2]
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.connect("/run/systemd/journal/socket")
        sock.send(
            (
                f"MESSAGE=New session {session_id} of user {user}.\n"
                "MESSAGE_ID=8d45620c1a4348dbb17410da57c60c66\n"
                f"SESSION_ID={session_id}\n"
                f"USER_ID={user}\n"
            ).encode()
        )
      '';
    in
    {
      checks = {
        login-alerts = pkgs.testers.runNixOSTest {
          name = "login-alerts";

          nodes.machine = {
            imports = [
              alertRecorder
              config.flake.modules.nixos.login-alerts
            ];

            environment.systemPackages = [ emitSession ];
            services.openssh.enable = true;
            users.users.conor.isNormalUser = true;
          };

          testScript = alertHelpers + ''
            import shlex


            def emit(tag, message):
                machine.succeed(f"systemd-cat -t {tag} echo {shlex.quote(message)}")


            def session(user, session_id):
                machine.succeed(f"emit-session {user} {session_id}")


            start_recorder()
            machine.wait_for_unit("login-alerts.service")
            machine.wait_for_unit("sshd.service")

            with subtest("a real ssh login is reported with its service and origin"):
                seen = len(posts())
                machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /root/id_test')
                machine.succeed(
                    "install -d -o conor -g users -m 700 /home/conor/.ssh && "
                    "install -o conor -g users -m 600 /root/id_test.pub "
                    "/home/conor/.ssh/authorized_keys"
                )
                # Held open, so the session still exists when the watcher looks
                # up its class, service and origin.
                machine.succeed(
                    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "
                    "-i /root/id_test conor@127.0.0.1 'sleep 30' >/dev/null 2>&1 &"
                )

                alert = wait_for_posts(seen + 1)[seen]
                assert alert["title"] == "machine: Login", alert
                assert alert["message"] == "conor logged in via sshd from 127.0.0.1", alert
                assert alert["priority"] == 4, alert
                assert alert["tags"] == ["key"], alert

            with subtest("the per-user manager session that login opened is not a login"):
                # A later, unrelated login proves the manager session was skipped
                # rather than merely lagging behind.
                session("marker", 900)
                new = wait_for_posts(seen + 2)[seen:]
                assert len(new) == 2, new
                assert new[1]["message"] == "marker logged in", new

            with subtest("a session that has already ended still names the user"):
                seen = len(posts())
                session("mallory", 901)
                alert = wait_for_posts(seen + 1)[seen]
                assert alert["title"] == "machine: Login", alert
                assert alert["message"] == "mallory logged in", alert

            with subtest("a tailscale grant names the tailnet identity and the local user"):
                seen = len(posts())
                emit(
                    "tailscaled",
                    'ssh-session(sess-1): access granted to tagged-devices as ssh-user "conor"',
                )
                alert = wait_for_posts(seen + 1)[seen]
                assert alert["title"] == "machine: Tailscale SSH login", alert
                assert alert["message"] == (
                    "tagged-devices logged in via Tailscale SSH as conor"
                ), alert
                assert alert["tags"] == ["key"], alert

            with subtest("a grant that names no local user still reports who"):
                seen = len(posts())
                emit("tailscaled", "ssh-session(conn=1): access granted to erin")
                alert = wait_for_posts(seen + 1)[seen]
                assert alert["message"] == "erin logged in via Tailscale SSH", alert

            with subtest("a tailscale login that also opens a session alerts once"):
                seen = len(posts())
                emit(
                    "tailscaled",
                    'ssh-session(sess-2): access granted to tagged-devices as ssh-user "dave"',
                )
                wait_for_posts(seen + 1)
                session("dave", 902)

                session("marker", 903)
                new = wait_for_posts(seen + 2)[seen:]
                assert len(new) == 2, new
                assert new[0]["title"] == "machine: Tailscale SSH login", new
                assert new[1]["message"] == "marker logged in", new

            with subtest("everything that is not a login stays quiet"):
                seen = len(posts())
                emit("tailscaled", "ssh-session(conn=3): access denied to mallory")
                emit("sshd", "Failed password for invalid user admin from 203.0.113.5 port 22 ssh2")
                emit("sudo", "conor : user NOT in sudoers ; TTY=pts/0 ; PWD=/ ; USER=root")
                emit("su", "FAILED su for root by conor")

                session("carol", 904)
                new = wait_for_posts(seen + 1)[seen:]
                assert len(new) == 1, new
                assert new[0]["message"] == "carol logged in", new

            with subtest("alerts are capped at ten per window"):
                machine.succeed("for i in $(seq 1 12); do emit-session flood$i 91$i; done")
                machine.wait_until_succeeds(
                    "journalctl --sync; journalctl -u login-alerts.service -o cat"
                    " | grep -q 'rate limit reached'"
                )
                assert len(posts()) == 10, posts()
          '';
        };

        alerts = pkgs.testers.runNixOSTest {
          name = "alerts";

          nodes.machine =
            {
              config,
              lib,
              pkgs,
              ...
            }:
            {
              imports = [ alertRecorder ];

              environment.systemPackages = [ config.blizzard.alerts.send ];

              systemd.services.canary = {
                description = "A unit that fails";
                unitConfig.OnFailure = "alert-failure@canary.service";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.coreutils}/bin/false";
                };
              };

              # Stands in for the hardened callers: spooling needs a write grant
              # that a sandboxed unit does not get for free.
              systemd.services.hardened-canary = {
                description = "A hardened unit that alerts";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${lib.getExe config.blizzard.alerts.send} Hardened 'sent from a sandbox' 4 key";
                  ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
                  NoNewPrivileges = true;
                  ProtectHome = true;
                  ProtectSystem = "strict";
                };
              };
            };

          testScript = alertHelpers + ''
            start_recorder()

            with subtest("a failing unit pages through the OnFailure template"):
                machine.fail("systemctl start canary.service")
                alert = wait_for_posts(1)[0]
                assert alert["title"] == "machine: Unit failed", alert
                assert "canary" in alert["message"], alert
                assert alert["priority"] == 4, alert
                assert alert["tags"] == ["warning"], alert

            with subtest("a delivered alert leaves nothing queued"):
                machine.fail("ls /var/lib/alert-spool/*.json")

            with subtest("an alert raised while ntfy is down is held, not lost"):
                seen = len(posts())
                machine.succeed("systemctl stop fake-ntfy.service")
                machine.succeed("alert-send Held 'raised during an outage' 3 key")
                machine.succeed("ls /var/lib/alert-spool/*.json")
                assert len(posts()) == seen, posts()

            with subtest("the queue drains once ntfy is reachable again"):
                machine.succeed("systemctl start fake-ntfy.service")
                machine.wait_for_open_port(8080)
                machine.succeed("systemctl start alert-drain.service")

                alert = wait_for_posts(seen + 1)[seen]
                assert alert["title"] == "machine: Held", alert
                assert alert["message"] == "raised during an outage", alert
                assert alert["priority"] == 3, alert
                assert alert["tags"] == ["key"], alert
                machine.fail("ls /var/lib/alert-spool/*.json")

            with subtest("a hardened caller can queue and deliver too"):
                seen = len(posts())
                machine.succeed("systemctl start hardened-canary.service")
                alert = wait_for_posts(seen + 1)[seen]
                assert alert["title"] == "machine: Hardened", alert
                assert alert["message"] == "sent from a sandbox", alert
                machine.fail("ls /var/lib/alert-spool/*.json")

            with subtest("a payload ntfy rejects is dropped rather than blocking the queue"):
                seen = len(posts())
                machine.succeed("echo not-json > /var/lib/alert-spool/00-poison.json")
                machine.succeed("alert-send Live 'queued behind the poison' 4 key")

                alert = wait_for_posts(seen + 1)[seen]
                assert alert["message"] == "queued behind the poison", alert
                machine.fail("ls /var/lib/alert-spool/*.json")

            with subtest("the retry timer is armed"):
                machine.wait_for_unit("alert-drain.timer")
          '';
        };
      };
    };
}
