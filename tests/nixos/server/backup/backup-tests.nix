{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
    in
    {
      checks.backup = pkgs.testers.runNixOSTest {
        name = "backup";

        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              alertRecorder
              config.flake.modules.nixos.backup
            ];

            environment.systemPackages = [
              pkgs.restic
              pkgs.sqlite
              pkgs.gzip
            ];
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

            blizzard.backup = {
              ntfyTopicFile = "/etc/restic-topic";
              jobs.service-data = {
                repository = "/var/restic-repo";
                paths = [ "/var/data" ];
                dumpPaths = [ "/var/dumps" ];
                passwordFile = "/etc/restic-password";
                pauseContainers = [ "dummy" ];
              };
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
          # Owner-only, like hister's tree.
          machine.succeed("mkdir -m 700 /var/data/private && echo 'secret' > /var/data/private/db && chmod 600 /var/data/private/db")
          # Glob characters, as in real album names.
          machine.succeed("mkdir -p '/var/data/music/Artist [Live]' && echo 'flac' > '/var/data/music/Artist [Live]/01 * Track.flac'")
          # Older than the snapshot, so the drill compares them.
          machine.succeed("find /var/data -exec touch -h -d '2020-01-01' {} +")
          machine.succeed("mkdir -p /var/dumps && sqlite3 /var/dumps/app.db 'CREATE TABLE t(x); INSERT INTO t VALUES (1);'")
          machine.succeed("printf 'SELECT 1;\\n-- PostgreSQL database dump complete\\n\\n' | gzip > /var/dumps/pg.sql.gz")
          # A .db that is not SQLite, with null bytes.
          machine.succeed("head -c 64 /dev/zero > /var/dumps/other.db")
          machine.succeed("install -d -o containers -g containers /var/restic-repo")

          with subtest("freshness alerts when the repository has no snapshots"):
              machine.succeed("systemctl start restic-freshness-service-data.service")
              alert = wait_for_posts(1)[0]
              assert alert["title"] == "machine: Backup stale", alert
              assert "no snapshots" in alert["message"], alert
              assert alert["priority"] == 4, alert

          with subtest("the first run initializes a fresh repository"):
              machine.succeed("systemctl start restic-backups-service-data.service")
              snapshots = as_containers("snapshots --json")
              assert '"paths"' in snapshots, snapshots

          with subtest("a successful backup stamps its status file"):
              stamp = int(machine.succeed("cat /var/lib/restic-status/service-data.backup"))
              assert abs(stamp - int(machine.succeed("date +%s"))) < 300, stamp

          with subtest("paused containers are stopped and started again"):
              machine.succeed("test -f /tmp/dummy-was-stopped")
              machine.wait_for_unit("dummy.service", user="containers")

          with subtest("owner-only files are backed up"):
              listing = as_root("ls latest /var/data/private")
              assert "/var/data/private/db" in listing, listing

          with subtest("the restore drill passes when files match"):
              before = len(posts())
              machine.succeed("systemctl start restic-restore-drill-service-data.service")
              journal = machine.succeed("journalctl -u restic-restore-drill-service-data.service")
              assert "2 databases intact" in journal, journal
              assert "null byte" not in journal, journal
              assert len(posts()) == before, posts()
              machine.succeed("test -f /var/lib/restic-status/service-data.drill")
              machine.succeed("test ! -s /var/lib/restic-status/service-data.drill")

          with subtest("the restore drill skips files written just before the snapshot"):
              # Containers restart after the ZFS snapshot, before restic stamps its time.
              taken = json.loads(as_root("snapshots --json --latest 1"))[0]["time"]
              machine.succeed("echo restarted > /var/data/family-photos")
              machine.succeed(f"touch -d @$(( $(date -d '{taken}' +%s) - 60 )) /var/data/family-photos")
              before = len(posts())
              machine.succeed("systemctl start restic-restore-drill-service-data.service")
              assert len(posts()) == before, posts()
              machine.succeed("echo irreplaceable > /var/data/family-photos && touch -d '2020-01-01' /var/data/family-photos")

          with subtest("the restore drill alerts when disk and backup differ"):
              before = len(posts())
              machine.succeed("echo 'rotted' > /var/data/private/db && touch -d '2020-01-01' /var/data/private/db")
              machine.succeed("systemctl start restic-restore-drill-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Restore drill failed", alert
              assert "1 restored files differ" in alert["message"], alert
              status = machine.succeed("cat /var/lib/restic-status/service-data.drill")
              assert "1 restored files differ" in status, status

          with subtest("the restore drill alerts on corrupt databases"):
              machine.succeed("head -c 4096 /var/dumps/app.db > /var/dumps/broken.db && head -c 20000 /dev/urandom >> /var/dumps/broken.db")
              machine.succeed("printf 'SELECT 1;\\n' | gzip > /var/dumps/cut.sql.gz")
              # Back up the rotted file too, so only databases fail.
              machine.succeed("systemctl start restic-backups-service-data.service")
              before = len(posts())
              machine.succeed("systemctl start restic-restore-drill-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Restore drill failed", alert
              assert "2 restored databases are corrupt" in alert["message"], alert
              machine.succeed("rm /var/dumps/broken.db /var/dumps/cut.sql.gz")

          with subtest("the backed-up file restores byte-identical"):
              machine.succeed("rm /var/data/family-photos")
              as_root("restore latest --target /var/restored")
              machine.succeed(
                  "echo irreplaceable | diff - /var/restored/var/data/family-photos"
              )

          with subtest("freshness stays quiet while the newest snapshot is recent"):
              before = len(posts())
              machine.succeed("systemctl start restic-freshness-service-data.service")
              assert len(posts()) == before, posts()

          with subtest("freshness alerts when a dump goes stale"):
              before = len(posts())
              machine.succeed("touch -d '3 days ago' /var/dumps/pg.sql.gz")
              machine.succeed("systemctl start restic-freshness-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Backup stale", alert
              assert "1 dumps over 26h old in /var/dumps" in alert["message"], alert
              machine.succeed("touch /var/dumps/pg.sql.gz")

          with subtest("freshness alerts when the newest snapshot is too old"):
              before = len(posts())
              machine.succeed("rm -rf /var/restic-repo && mkdir -p /var/restic-repo")
              as_root("init")
              as_root("backup --time '2020-01-01 00:00:00' /var/restored")
              machine.succeed("systemctl start restic-freshness-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Backup stale", alert
              assert "newest snapshot is" in alert["message"], alert

          with subtest("the restore drill alerts when a path is missing"):
              before = len(posts())
              machine.succeed("systemctl start restic-restore-drill-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Restore drill failed", alert
              assert "2 backup paths missing" in alert["message"], alert

          with subtest("a failed backup pages through OnFailure"):
              before = len(posts())
              machine.succeed("chmod 000 /var/restic-repo")
              machine.fail("systemctl start restic-backups-service-data.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Backup failed", alert
              assert "restic backup service-data failed" in alert["message"], alert
        '';
      };

      checks.backup-zfs = pkgs.testers.runNixOSTest {
        name = "backup-zfs";

        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              alertRecorder
              config.flake.modules.nixos.backup
            ];

            boot.supportedFilesystems = [ "zfs" ];
            networking.hostId = "8425e349";
            virtualisation.emptyDiskImages = [ 1024 ];

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

            # Writes on start, like an app after restart.
            systemd.user.services.dummy = {
              description = "Pretend container";
              wantedBy = [ "default.target" ];
              serviceConfig = {
                ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
                ExecStartPost = "-${pkgs.bash}/bin/sh -c 'echo started > /var/data/app/state'";
              };
            };

            blizzard.backup = {
              ntfyTopicFile = "/etc/restic-topic";
              jobs.service-data = {
                repository = "/var/restic-repo";
                paths = [ "/var/data" ];
                zfsDatasets."tank/data" = "/var/data";
                passwordFile = "/etc/restic-password";
                pauseContainers = [ "dummy" ];
              };
            };
          };

        testScript = ''
          ENV = "RESTIC_REPOSITORY=/var/restic-repo RESTIC_PASSWORD_FILE=/etc/restic-password"


          def dump(path):
              return machine.succeed(f"{ENV} restic dump latest {path}")


          def monotonic(unit, prop, user=False):
              scope = "--user -M containers@" if user else ""
              return int(machine.succeed(f"systemctl {scope} show {unit} -p {prop} --value"))


          machine.wait_for_unit("multi-user.target")
          machine.succeed("zpool create -O mountpoint=none tank /dev/vdb")
          machine.succeed("zfs create -o mountpoint=/var/data tank/data")
          machine.succeed("install -d -o containers -g containers /var/data/app /var/restic-repo")
          machine.succeed("echo before > /var/data/app/state && chown containers /var/data/app/state")
          machine.wait_for_unit("dummy.service", user="containers")

          with subtest("restic reads the snapshot, not the live files"):
              machine.succeed("systemctl start restic-backups-service-data.service")
              assert dump("/var/data/app/state") == "before\n"
              machine.succeed("grep -qx started /var/data/app/state")

          with subtest("containers are back before restic reads"):
              up = monotonic("dummy.service", "ActiveEnterTimestampMonotonic", user=True)
              read = monotonic("restic-backups-service-data.service", "ExecMainStartTimestampMonotonic")
              assert 0 < up < read, (up, read)

          with subtest("a second run replaces the snapshot"):
              machine.succeed("echo second > /var/data/app/later")
              machine.succeed("systemctl start restic-backups-service-data.service")
              assert dump("/var/data/app/later") == "second\n"
              count = machine.succeed("zfs list -H -t snapshot -o name | grep -c @restic").strip()
              assert count == "1", count
        '';
      };
    };
}
