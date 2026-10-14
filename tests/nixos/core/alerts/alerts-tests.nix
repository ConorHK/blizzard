{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.alerts = pkgs.testers.runNixOSTest {
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
}
