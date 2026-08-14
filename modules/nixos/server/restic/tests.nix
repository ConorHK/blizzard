{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.restic = pkgs.testers.runNixOSTest {
        name = "restic";

        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              alertRecorder
              config.flake.modules.nixos.restic
            ];

            environment.systemPackages = [ pkgs.restic ];
            environment.etc = {
              "restic-password".text = "correct-horse-battery-staple";
              "restic-topic".text = "NTFY_TOPIC=restic-test";
            };

            users.users.containers = {
              isNormalUser = true;
              group = "containers";
              linger = true;
            };
            users.groups.containers = { };

            # Stands in for a quadlet container: proves the pause hooks reach the
            # rootless user manager and put it back afterwards.
            systemd.user.services.dummy = {
              description = "Pretend container";
              wantedBy = [ "default.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
                ExecStopPost = "${pkgs.coreutils}/bin/touch /tmp/dummy-was-stopped";
              };
            };

            restic = {
              repository = "/var/restic-repo";
              paths = [ "/var/data" ];
              passwordFile = "/etc/restic-password";
              ntfyTopicFile = "/etc/restic-topic";
              pauseContainers = [ "dummy" ];
            };
          };

        testScript = alertHelpers + ''
          REPO = "/var/restic-repo"
          ENV = f"RESTIC_REPOSITORY={REPO} RESTIC_PASSWORD_FILE=/etc/restic-password"


          def as_root(args):
              return machine.succeed(f"{ENV} restic {args}")


          def as_containers(args):
              return machine.succeed(
                  f"su containers -s /bin/sh -c '{ENV} restic {args}'"
              )


          start_recorder()
          machine.succeed("mkdir -p /var/data && echo 'irreplaceable' > /var/data/family-photos")
          machine.succeed("install -d -o containers -g containers /var/restic-repo")

          with subtest("freshness alerts when the repository has no snapshots"):
              machine.succeed("systemctl start restic-backups-freshness.service")
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Backup stale", alert
              assert "no snapshots" in alert["message"], alert
              assert alert["priority"] == 4, alert

          with subtest("the first run initializes a fresh repository"):
              machine.succeed("systemctl start restic-backups-service-data.service")
              snapshots = as_containers("snapshots --json")
              assert '"paths"' in snapshots, snapshots

          with subtest("paused containers are stopped and started again"):
              machine.succeed("test -f /tmp/dummy-was-stopped")
              machine.wait_for_unit("dummy.service", user="containers")

          with subtest("the backed-up file restores byte-identical"):
              machine.succeed("rm /var/data/family-photos")
              as_root("restore latest --target /var/restored")
              machine.succeed(
                  "echo irreplaceable | diff - /var/restored/var/data/family-photos"
              )

          with subtest("freshness stays quiet while the newest snapshot is recent"):
              before = len(posts())
              machine.succeed("systemctl start restic-backups-freshness.service")
              assert len(posts()) == before, posts()

          with subtest("freshness alerts when the newest snapshot is too old"):
              machine.succeed("rm -rf /var/restic-repo && mkdir -p /var/restic-repo")
              as_root("init")
              as_root("backup --time '2020-01-01 00:00:00' /var/restored")
              machine.succeed("systemctl start restic-backups-freshness.service")
              alert = wait_for_posts(2)[1]
              assert alert["title"] == "machine: Backup stale", alert
              assert "backup has not run" in alert["message"], alert

          with subtest("a failed backup pages through OnFailure"):
              before = len(posts())
              machine.succeed("chmod 000 /var/restic-repo")
              machine.fail("systemctl start restic-backups-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Backup failed", alert
              assert "restic backup service-data failed" in alert["message"], alert
        '';
      };
    };
}
