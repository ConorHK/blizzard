_: {
  flake.modules.nixos.zfs-alerts =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # ZED pipes the report on stdin.
      relay = pkgs.writeShellApplication {
        name = "zed-alert";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
        ];
        text = ''
          subject=$1
          report=$(head -c 3000)
          priority=4
          # Resilvers report even when healthy.
          case $subject in
            *" resilver_finish event "*) priority=3 ;;
          esac
          alert-send "ZFS" "$subject"$'\n\n'"$report" "$priority" warning
        '';
      };
    in
    {
      config = lib.mkIf config.boot.zfs.enabled {
        # Scrub, fault and data events page.
        services.zfs.zed.settings = {
          ZED_NOTIFY_DATA = true;
          ZED_EMAIL_ADDR = [ "root" ];
          ZED_EMAIL_PROG = lib.getExe relay;
          ZED_EMAIL_OPTS = "'@SUBJECT@'";
        };
      };
    };
}
