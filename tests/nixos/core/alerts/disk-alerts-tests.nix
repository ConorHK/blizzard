{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.disk-alerts = pkgs.testers.runNixOSTest {
        name = "disk-alerts";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.disk-alerts
          ];

          virtualisation.fileSystems."/small" = {
            fsType = "tmpfs";
            options = [ "size=10M" ];
          };
          blizzard.diskAlerts.mounts = [ "/small" ];
        };

        testScript = alertHelpers + ''
          start_recorder()

          def check():
              machine.succeed("systemctl start disk-alerts.service")

          with subtest("a roomy disk stays quiet"):
              check()
              machine.sleep(2)
              assert posts() == [], posts()

          with subtest("a full disk pages once"):
              machine.succeed("fallocate -l 9500K /small/fill")
              check()
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Disk full", alert
              assert "/small" in alert["message"], alert
              check()
              machine.sleep(2)
              assert len(posts()) == 1, posts()

          with subtest("freeing space clears the stamp"):
              machine.succeed("rm /small/fill")
              check()
              machine.fail("ls /var/lib/disk-alerts/small")
        '';
      };
    };
}
