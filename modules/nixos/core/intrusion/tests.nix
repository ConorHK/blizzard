{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks = {
        tripwire = pkgs.testers.runNixOSTest {
          name = "tripwire";

          nodes.machine = {
            imports = [
              alertRecorder
              config.flake.modules.nixos.tripwire
            ];
            blizzard.tripwire.scanRoots = [ "/var/scan" ];
          };

          testScript = alertHelpers + ''

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


            start_recorder()
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

        auth-alerts = pkgs.testers.runNixOSTest {
          name = "auth-alerts";

          nodes.machine.imports = [
            alertRecorder
            config.flake.modules.nixos.auth-alerts
          ];

          testScript = alertHelpers + ''
            import shlex


            def emit(tag, message):
                machine.succeed(f"systemd-cat -t {tag} echo {shlex.quote(message)}")


            start_recorder()
            machine.wait_for_unit("auth-alerts.service")

            with subtest("an accepted sshd login is reported"):
                emit("sshd", "Accepted publickey for conor from 100.64.0.1 port 43210 ssh2")
                alert = wait_for_posts(1)[0]
                assert alert["title"] == "machine: SSH login", alert
                assert alert["priority"] == 4, alert
                assert alert["tags"] == ["key"], alert

            with subtest("a failed sshd login is a lower-priority warning"):
                emit("sshd", "Failed password for invalid user admin from 203.0.113.5 port 22 ssh2")
                alert = wait_for_posts(2)[1]
                assert alert["title"] == "machine: SSH auth failure", alert
                assert alert["priority"] == 3, alert
                assert alert["tags"] == ["warning"], alert

            with subtest("a sudo refusal is a privilege escalation failure"):
                emit("sudo", "conor : user NOT in sudoers ; TTY=pts/0 ; PWD=/ ; USER=root")
                alert = wait_for_posts(3)[2]
                assert alert["title"] == "machine: Privilege escalation failure", alert
                assert alert["priority"] == 4, alert

            with subtest("tailscale grants and denials are distinguished"):
                emit("tailscaled", "ssh-session(conn=1): access granted to conor")
                alert = wait_for_posts(4)[3]
                assert alert["title"] == "machine: Tailscale SSH login", alert
                assert alert["message"].startswith("tailscale: "), alert
                assert alert["tags"] == ["key"], alert

                emit("tailscaled", "ssh-session(conn=2): access denied to mallory")
                alert = wait_for_posts(5)[4]
                assert alert["title"] == "machine: Tailscale SSH denied", alert
                assert alert["tags"] == ["warning"], alert

            with subtest("tailscaled chatter cannot forge an sshd alert"):
                # Ordering guard: tailscaled echoes whole commands, so a command
                # containing an sshd pattern must be consumed by the prefix branch.
                emit("tailscaled", "ssh-session(conn=3): starting: grep 'Failed password' /var/log")
                emit("sshd", "Connection closed by 10.0.0.1 port 1234 [preauth]")
                # A line that does alert, proving the pipeline processed the two above.
                emit("su", "FAILED su for root by conor")
                alert = wait_for_posts(6)[5]
                assert alert["title"] == "machine: Privilege escalation failure", alert
                assert len(posts()) == 6, posts()

            with subtest("alerts are capped at ten per window"):
                machine.succeed(
                    "for i in $(seq 1 10); do "
                    "systemd-cat -t sshd echo \"Failed password for bot$i from 203.0.113.9 port 22 ssh2\"; "
                    "done"
                )
                wait_for_posts(10)
                machine.wait_until_succeeds(
                    "journalctl --sync; journalctl -u auth-alerts.service -o cat"
                    " | grep -q 'rate limit reached'"
                )
                assert len(posts()) == 10, posts()
          '';
        };

        alerts = pkgs.testers.runNixOSTest {
          name = "alerts";

          nodes.machine =
            { pkgs, ... }:
            {
              imports = [ alertRecorder ];

              systemd.services.canary = {
                description = "A unit that fails";
                unitConfig.OnFailure = "alert-failure@canary.service";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${pkgs.coreutils}/bin/false";
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
          '';
        };
      };
    };
}
