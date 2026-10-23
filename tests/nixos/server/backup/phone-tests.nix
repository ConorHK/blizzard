{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (config.flake.testSupport) alertRecorder alertHelpers;
      inherit (config.flake.modules.nixos) alerts backup backup-phone;

      withoutSyncthing = pkgs.nixos {
        imports = [
          alerts
          backup
          backup-phone
        ];
        blizzard.alerts.topicFile = "/dev/null";
        blizzard.backup = {
          ntfyTopicFile = "/dev/null";
          jobs.phone = {
            repository = "/var/repo";
            passwordFile = "/dev/null";
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "tmpfs";
        };
        system.stateVersion = "25.05";
      };
      failed = map (a: a.message) (builtins.filter (a: !a.assertion) withoutSyncthing.config.assertions);
    in
    {
      checks.backup-phone-needs-syncthing =
        assert builtins.any (pkgs.lib.hasPrefix "backup-phone needs services.syncthing") failed;
        pkgs.runCommand "backup-phone-needs-syncthing" { } "touch $out";

      checks.backup-phone = pkgs.testers.runNixOSTest {
        name = "backup-phone";

        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              alertRecorder
              backup
              backup-phone
            ];

            environment.systemPackages = [ pkgs.restic ];
            environment.etc = {
              "restic-password".text = "correct-horse-battery-staple";
              "restic-topic".text = "NTFY_TOPIC=restic-test";
            };

            services.syncthing = {
              enable = true;
              settings.devices.banshee.id = config.flake.lib.syncthingDevices.banshee;
            };

            blizzard.backup = {
              ntfyTopicFile = "/etc/restic-topic";
              jobs.phone = {
                repository = "/var/restic-repo";
                passwordFile = "/etc/restic-password";
              };
            };
          };

        testScript = alertHelpers + ''
          DIR = "/var/lib/syncthing/phone-backup"
          ENV = "RESTIC_REPOSITORY=/var/restic-repo RESTIC_PASSWORD_FILE=/etc/restic-password"


          def freshness():
              before = len(posts())
              machine.succeed("systemctl start restic-freshness-phone.service")
              return [p["message"] for p in posts()[before:]]


          start_recorder()

          with subtest("syncthing gets a receive-only folder for the phone"):
              machine.wait_for_unit("syncthing-init.service")
              machine.wait_until_succeeds(f"test -d {DIR}/.stfolder")
              machine.succeed(
                  "grep -q 'id=\"phone-backup\".*type=\"receiveonly\"' /var/lib/syncthing/.config/syncthing/config.xml"
              )

          with subtest("a job with no paths gets no units"):
              machine.fail("systemctl cat restic-backups-service-data.service")

          with subtest("freshness alerts before anything arrives"):
              messages = freshness()
              assert any(m == f"No files in {DIR}" for m in messages), messages
              assert any("phone: no snapshots" in m for m in messages), messages

          with subtest("the backup captures phone files, not syncthing markers"):
              machine.succeed(f"echo export > {DIR}/chunk && chown syncthing {DIR}/chunk && chmod 600 {DIR}/chunk")
              machine.succeed("systemctl start restic-backups-phone.service")
              listing = machine.succeed(f"{ENV} restic ls latest")
              assert f"{DIR}/chunk" in listing, listing
              assert ".stfolder" not in listing, listing

          with subtest("freshness stays quiet when files and snapshot are new"):
              assert freshness() == [], posts()

          with subtest("freshness stays quiet for a 13 day gap"):
              machine.succeed(f"touch -d '13 days ago' {DIR}/chunk")
              assert freshness() == [], posts()

          with subtest("freshness alerts when the phone stops sending"):
              machine.succeed(f"touch -d '15 days ago' {DIR}/chunk")
              messages = freshness()
              assert messages == [f"No new files in {DIR} for 360h"], messages

          with subtest("a failed backup pages"):
              before = len(posts())
              machine.succeed("rm /etc/restic-password")
              machine.fail("systemctl start restic-backups-phone.service")
              alert = wait_for_posts(before + 1)[before]
              assert alert["title"] == "machine: Backup failed", alert
              assert "restic backup phone failed" in alert["message"], alert
        '';
      };
    };
}
