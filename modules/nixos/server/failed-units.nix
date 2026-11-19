_: {
  flake.modules.nixos.failed-units =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      check = pkgs.writeShellApplication {
        name = "failed-units-check";
        runtimeInputs = [
          config.blizzard.alerts.send
          pkgs.coreutils
          pkgs.systemd
        ];
        text = ''
          state=''${STATE_DIRECTORY:?}

          mapfile -t failed < <(systemctl list-units --state=failed --plain --no-legend --full | cut -d' ' -f1)

          for unit in "''${failed[@]}"; do
            # Units with an OnFailure hook already paged when they failed.
            if [ -n "$(systemctl show -P OnFailure "$unit")" ] || [ -e "$state/$unit" ]; then
              continue
            fi
            alert-send "Unit failed" "$unit failed, check journalctl -u $unit" 4 warning
            touch "$state/$unit"
          done

          for stamp in "$state"/*; do
            [ -e "$stamp" ] || break
            unit=''${stamp##*/}
            if ! printf '%s\n' "''${failed[@]}" | grep -qxF "$unit"; then
              rm "$stamp"
            fi
          done
        '';
      };
    in
    {
      systemd = {
        services.failed-units = {
          description = "Alert on failed units with no OnFailure hook";
          unitConfig.OnFailure = "alert-failure@%n";
          serviceConfig = {
            Type = "oneshot";
            StateDirectory = "failed-units";
            ExecStart = lib.getExe check;
          };
        };
        timers.failed-units = {
          description = "Hourly failed unit check";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "15min";
            OnUnitActiveSec = "1h";
          };
        };
      };
    };
}
