{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.zfs-alerts = pkgs.testers.runNixOSTest {
        name = "zfs-alerts";

        nodes.machine = {
          imports = [
            alertRecorder
            config.flake.modules.nixos.zfs-alerts
          ];

          boot.supportedFilesystems = [ "zfs" ];
          networking.hostId = "8425e349";
          virtualisation.memorySize = 2048;
        };

        testScript = alertHelpers + ''
          start_recorder()
          machine.wait_for_unit("zfs-zed.service")
          machine.succeed(
              "truncate -s 128M /root/a /root/b",
              "zpool create tank mirror /root/a /root/b",
          )

          with subtest("a healthy pool stays quiet"):
              machine.succeed("zpool scrub -w tank")
              machine.sleep(5)
              assert posts() == [], posts()

          with subtest("a faulted vdev pages through alert-send"):
              machine.succeed("zpool offline -f tank /root/b")
              alert = wait_for_posts(1, timeout=60)[0]
              assert alert["title"] == "machine: ZFS", alert
              assert "tank" in alert["message"], alert
              assert "FAULTED" in alert["message"], alert
              assert alert["priority"] == 4, alert
        '';
      };
    };
}
