{ config, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (config.flake.modules.nixos) alerts backup backup-home;

      host = pkgs.nixos {
        imports = [
          alerts
          backup
          backup-home
        ];
        networking.hostName = "desk";
        users.users.goose.isNormalUser = true;
        blizzard.alerts.topicFile = "/dev/null";
        blizzard.backup = {
          ntfyTopicFile = "/dev/null";
          jobs.home = {
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
      inherit (host.config) systemd blizzard;
      job = host.config.services.restic.backups.home;
    in
    {
      checks.backup-home =
        assert
          job.paths == map (d: "/home/goose/${d}") [
            ".ssh"
            ".gnupg"
            "docs"
            "media"
            "backup"
          ];
        assert lib.elem "/home/goose/media/games" job.exclude;
        assert blizzard.backup.jobs.home.bucket == "restic-backup-desk";
        # Desktops sit off for days.
        assert !(systemd.services ? restic-freshness-home);
        assert !(systemd.timers ? restic-freshness-home);
        assert systemd.services ? restic-restore-drill-home;
        assert lib.elem "d /home/goose/backup 0700 goose goose -" systemd.tmpfiles.rules;
        pkgs.runCommand "backup-home" { } "touch $out";
    };
}
