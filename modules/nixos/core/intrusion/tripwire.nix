_: {
  flake.modules.nixos.tripwire =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.blizzard.tripwire;

      # Credentials and privilege change only on deploy, so they can be checked
      # often; the volatile categories keep the quiet nightly slot.
      checks = {
        fast = {
          description = "Drift check: credentials, keys and setuid binaries";
          OnCalendar = "*:0/15";
          RandomizedDelaySec = "60s";
        };
        full = {
          description = "Drift check: full system state";
          # Clear of nh clean (00:00), dawarich (02:45) and the restic run at
          # 03:00 that pauses containers, plus every autoUpgrade window.
          OnCalendar = "01:30";
          RandomizedDelaySec = "10m";
        };
      };

      check = pkgs.writeShellApplication {
        name = "tripwire";
        runtimeInputs = with pkgs; [
          coreutils
          diffutils
          findutils
          getent
          gnugrep
          gnused
          gawk
          iproute2
          kmod
          openssh
          systemd
          config.blizzard.alerts.send
        ];
        text = ''
          umask 077
          mode=$1
          case $mode in
            fast | full) ;;
            *)
              echo "usage: tripwire fast|full" >&2
              exit 2
              ;;
          esac

          state=/var/lib/tripwire
          baseline=$state/baseline-$mode
          manifest=$(mktemp)
          trap 'rm -f "$manifest"' EXIT

          {
            getent passwd | cut -d: -f1,3,4,6,7 | sed 's/^/passwd: /'
            getent group | cut -d: -f1,3 | sed 's/^/group: /'
            sha256sum /etc/shadow | awk '{ print "shadow-digest: " $1 }'
            sha256sum /etc/sudoers | awk '{ print "sudoers-digest: " $1 }'
            [ -f /etc/ssh/sshd_config ] && sha256sum /etc/ssh/sshd_config |
              awk '{ print "sshd-config-digest: " $1 }' || true

            for f in /etc/ssh/authorized_keys.d/*; do
              [ -f "$f" ] || continue
              ssh-keygen -lf "$f" 2>/dev/null | sed "s|^|authorized-key ''${f##*/}: |" || true
            done

            getent passwd | while IFS=: read -r user _ _ _ _ home _; do
              [ -f "$home/.ssh/authorized_keys" ] || continue
              ssh-keygen -lf "$home/.ssh/authorized_keys" 2>/dev/null | sed "s|^|authorized-key $user: |" || true
            done

            for f in /etc/ssh/ssh_host_*_key.pub; do
              [ -f "$f" ] || continue
              ssh-keygen -lf "$f" 2>/dev/null | sed 's/^/host-key: /' || true
            done

            # Container image layers ship their own setuid binaries and churn on
            # every pull; the store can't hold setuid files at all.
            for root in ${lib.escapeShellArgs cfg.scanRoots}; do
              [ -d "$root" ] || continue
              find "$root" -xdev \
                \( -path /nix/store -o -path '*/.local/share/containers' -o -path /var/lib/containers \) -prune \
                -o -type f -perm /6000 -printf 'setuid: %p %m %u:%g\n' 2>/dev/null || true
            done

            find /run/wrappers/bin/ -maxdepth 1 -type f -perm /6000 \
              -printf 'wrapper: %p %m %u:%g\n' 2>/dev/null || true

            # Everything below changes on its own — containers cycle, modules load
            # on hotplug — so it only runs daily, when the system is quiet.
            if [ "$mode" = full ]; then
              # Externally reachable listeners only; ephemeral ports and the mDNS
              # groups every desktop app joins would otherwise churn daily.
              ss -Hltunp 2>/dev/null \
                | sed -E 's/pid=[0-9]+,fd=[0-9]+//g; s/[[:space:]]+/ /g' \
                | awk '{ n = split($5, a, ":"); port = a[n] + 0;
                         if (port > 0 && port < 32768 && $5 !~ /^(127\.|\[::1\]|22[4-9]\.|23[0-9]\.|\[ff)/)
                           print "listener: " $1, $5, $7 }' || true

              systemctl list-unit-files --state=enabled --no-legend --no-pager \
                | awk '{ print "unit: " $1 }' || true

              lsmod | awk 'NR > 1 { print "module: " $1 }' || true

              find /etc -maxdepth 1 -mindepth 1 ! -type l -printf 'etc-mutable: %p\n' 2>/dev/null || true
            fi
          } | sort -u > "$manifest"

          if [ ! -f "$baseline" ]; then
            cp "$manifest" "$baseline"
            echo "tripwire[$mode]: baseline created, $(wc -l < "$baseline") entries"
            exit 0
          fi

          if diff -u "$baseline" "$manifest" > "$state/last-diff-$mode"; then
            echo "tripwire[$mode]: no drift"
            exit 0
          fi

          summary=$(grep -E '^[+-][^+-]' "$state/last-diff-$mode" | head -n 25 | cut -c 1-160 || true)
          alert-send "System drift detected ($mode)" "$summary" 4 rotating_light
          cp "$manifest" "$baseline"
        '';
      };
    in
    {
      options.blizzard.tripwire.scanRoots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "/"
          "/home"
          "/persist"
        ];
        description = "Filesystem roots scanned for setuid binaries, each without crossing mount points.";
      };

      config = {
        systemd = {
          services = lib.mapAttrs' (
            mode: m:
            lib.nameValuePair "tripwire-${mode}" {
              inherit (m) description;
              unitConfig.OnFailure = "alert-failure@tripwire-${mode}.service";
              # Persistent catch-up fires early at boot, before the network is up.
              after = [
                "network-online.target"
                "agenix-install-secrets.service"
              ];
              wants = [ "network-online.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${lib.getExe check} ${mode}";
                StateDirectory = "tripwire";
                StateDirectoryMode = "0700";
                Nice = 19;
                IOSchedulingClass = "idle";
              };
            }
          ) checks;

          timers = lib.mapAttrs' (
            mode: m:
            lib.nameValuePair "tripwire-${mode}" {
              inherit (m) description;
              wantedBy = [ "timers.target" ];
              timerConfig = {
                inherit (m) OnCalendar RandomizedDelaySec;
                Persistent = true;
              };
            }
          ) checks;
        };
      };
    };
}
