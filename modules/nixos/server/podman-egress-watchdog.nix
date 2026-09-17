_: {
  flake.modules.nixos.podman-egress-watchdog =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # aardvark-dns shares each rootless netns, so probing it tests
      # container egress. leprechaun 2026-09-17: that netns lost its
      # default route on a wifi flap and every container went dark.
      probe = pkgs.writeShellApplication {
        name = "podman-egress-probe";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.iproute2
          pkgs.iputils
          pkgs.procps
          pkgs.util-linux
        ];
        text = ''
          set -euo pipefail
          target=''${1:-1.1.1.1}
          state_dir=/var/lib/podman-egress-watchdog
          state=$state_dir/broken
          mkdir -p "$state_dir"

          was_broken=0
          if [ -e "$state" ]; then
            was_broken=1
          fi

          mapfile -t pids < <(pgrep -x aardvark-dns || true)
          if [ ''${#pids[@]} -eq 0 ]; then
            echo "no aardvark-dns running; nothing to probe"
            exit 0
          fi

          failed=0
          for pid in "''${pids[@]}"; do
            owner=$(ps -o user= -p "$pid")
            owner="''${owner//[[:space:]]/}"
            if nsenter -t "$pid" -n -- ping -c1 -W3 "$target" >/dev/null 2>&1; then
              echo "egress ok: aardvark-dns $pid ($owner)"
            else
              failed=1
              echo "egress FAILED: aardvark-dns $pid ($owner)"
              # Snapshot: evidence last outage lacked.
              echo "--- netns routes ---"
              nsenter -t "$pid" -n -- ip route || true
              echo "--- netns links ---"
              nsenter -t "$pid" -n -- ip -br addr || true
            fi
          done

          if [ "$failed" -eq 1 ]; then
            touch "$state"
            # Page once per outage; timer reruns meanwhile.
            if [ "$was_broken" -eq 0 ]; then
              alert-send "Podman egress down" \
                "Rootless containers cannot reach the internet. Routes logged to journal." \
                4 zap
            fi
            exit 1
          fi

          if [ "$was_broken" -eq 1 ]; then
            rm -f "$state"
            alert-send "Podman egress back" "Rootless container egress recovered." 3 "+1"
          fi
        '';
      };
    in
    {
      systemd.services.podman-egress-watchdog = {
        description = "Probe rootless podman netns egress";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe probe;
          StateDirectory = "podman-egress-watchdog";
          ReadWritePaths = [ config.blizzard.alerts.spoolDir ];
          ProtectSystem = "strict";
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };

      systemd.timers.podman-egress-watchdog = {
        description = "Probe rootless podman netns egress every 5 minutes";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "5min";
          Persistent = true;
        };
      };

      environment.systemPackages = [ probe ];
    };
}
