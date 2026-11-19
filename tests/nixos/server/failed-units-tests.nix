{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.failed-units = pkgs.testers.runNixOSTest {
        name = "failed-units";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.failed-units
          ];

          systemd.services = {
            breaks = {
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.coreutils}/bin/test -e /run/fixed";
              };
            };
            hooked = {
              unitConfig.OnFailure = "alert-failure@%n";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.coreutils}/bin/false";
              };
            };
          };
        };

        testScript = alertHelpers + ''
          start_recorder()

          def check():
              machine.succeed("systemctl start failed-units.service")

          with subtest("no failed units stays quiet"):
              check()
              machine.sleep(2)
              assert posts() == [], posts()

          with subtest("a failed unit pages once"):
              machine.fail("systemctl start breaks.service")
              check()
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Unit failed", alert
              assert "breaks.service" in alert["message"], alert
              check()
              machine.sleep(2)
              assert len(posts()) == 1, posts()

          with subtest("a unit with an OnFailure hook pages only through it"):
              machine.fail("systemctl start hooked.service")
              wait_for_posts(2)
              check()
              machine.sleep(2)
              assert len(posts()) == 2, posts()

          with subtest("recovery clears the stamp"):
              machine.succeed("touch /run/fixed")
              machine.succeed("systemctl start breaks.service")
              check()
              machine.fail("ls /var/lib/failed-units/breaks.service")
        '';
      };
    };
}
