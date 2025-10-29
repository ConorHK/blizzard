{
  flake.modules.homeManager.waybar =
    { lib, pkgs, ... }:
    {

      systemd.user.services.waybar = {
        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };

      stylix.targets.waybar.enable = lib.mkForce false;
      programs.waybar = {
        enable = true;
        systemd.enable = true;
        style = builtins.readFile ./style.css;
        settings.main =
          let
            workspace-display = pkgs.writeShellScriptBin "workspace-display" ''
                  #!/usr/bin/env bash

              primary=$1

              # Get all workspaces
              all_workspaces=$(hyprctl workspaces -j | ${pkgs.jq}/bin/jq -r 'sort_by(.id) | .[].id')

              # Get active workspace
              active=$(hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r '.id')

              # Check if primary workspace exists
              primary_exists=$(echo "$all_workspaces" | grep -c "^$primary$")

              if [ $primary_exists -eq 0 ]; then
                exit 1
              fi

              # Build display: primary dot
              display="•"

              # Count children (workspaces that are primary + additional digits)
              child_count=0
              for ws in $all_workspaces; do
                # Get the first digit(s) that represent the primary workspace
                # A child must have exactly (primary_length + 1) or more digits and start with primary
                if [[ "$ws" =~ ^''${primary}[0-9]+$ ]] && [ "''${#ws}" -gt "''${#primary}" ]; then
                  child_count=$((child_count + 1))
                fi
              done

              # Add one dot for each child
              for ((i=0; i<child_count; i++)); do
                display="$display•"
              done

              # Check if active workspace is in this primary tree
              if [[ "$active" =~ ^''${primary}[0-9]*$ ]]; then
                # Active - highlight
                echo "<span foreground='#ff0000'>$display</span>"
              else
                # Inactive
                echo "$display"
              fi
            '';
          in
          {
            name = "sidebar";
            layer = "top";
            position = "left";
            spacing = 5;
            modules-left = [
              "clock"
            ];
            modules-center = [
              "custom/hyprland-workspace-1"
              "custom/hyprland-workspace-2"
              "custom/hyprland-workspace-3"
            ];
            modules-right = [
              "privacy"
              "wireplumber"
              "network"
              "custom/separator"
              "systemd-failed-units"
              "custom/system-up-to-date"
            ];
            "hyprland/workspaces" = {
              disable-scroll = true;
              on-click = "activate";
              persistent-only = true;
              persistent-workspaces = {
                "1" = [ ];
                "2" = [ ];
                "3" = [ ];
              };
              format = "{icon}";
              format-icons = {
                active = "•";
                default = "•";
              };
              sort-by-number = true;
            };
            "custom/hyprland-workspace-1" = {
              format = "{}";
              exec = "${lib.getExe workspace-display} 1";
              interval = 1;
              return-type = "";
            };
            "custom/hyprland-workspace-2" = {
              format = "{}";
              exec = "${lib.getExe workspace-display} 2";
              interval = 1;
              return-type = "";
            };
            "custom/hyprland-workspace-3" = {
              format = "{}";
              exec = "${lib.getExe workspace-display} 3";
              interval = 1;
              return-type = "";
            };
            clock = {
              format = "{:%H\n%M\n--\n%d\n%m}";
              tooltip-format = "<big>{:%A %B %d}</big>\n<tt><small>{calendar}</small></tt>";
            };
            network = {
              interval = 1;
              format = "";
              format-ethernet = "e:con";
              format-wifi = "w:con";
              format-disconnected = "n:dis";
              tooltip-format-wifi = "{essid} ({signalStrength}%)";
              tooltip-format-ethernet = "{ifname}";
              tooltip-format-disconnected = "disconnected";
            };
            wireplumber = {
              format = "v:{volume}%";
              format-muted = "m:{volume}%";
              max-volume = 100;
              scroll-step = 5;
              on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
              on-click-right = "${lib.getExe pkgs.pwvucontrol}";
            };
            battery = {
              states = {
                good = 70;
                warning = 30;
                critical = 15;
              };
              format = "b:{capacity}%";
              format-charging = "c:{capacity}%";
            };
            privacy = {
              modules = [
                {
                  type = "screenshare";
                  tooltip = true;
                }
              ];
            };
            "custom/system-up-to-date" =
              let
                check-flake-updates = pkgs.writeShellScriptBin "check-flake-updates" (
                  builtins.readFile ./check-flake-updates.sh
                );
                git-status = pkgs.writeShellScriptBin "gitstatus" ''
                  #!/usr/bin/env bash

                  cd /home/goose/repositories/blizzard && git fetch origin && git status
                  read -n 1 -s -r -p "Press any key to exit"
                '';
              in
              {
                format = "{}";
                exec = "${lib.getExe check-flake-updates} $HOME/repositories/blizzard origin";
                exec-if = "test -d $HOME/repositories/blizzard/.git";
                interval = 300;
                tooltip = true;
                on-click = "${lib.getExe pkgs.alacritty} --class alacritty-popup -e ${lib.getExe git-status}";
                return-type = "json";
              };
            systemd-failed-units =
              let
                check-failing-units = pkgs.writeShellScriptBin "check-failing-units" ''
                  #!/usr/bin/env bash


                  BLUE_BOLD="\033[1;34m"
                  RESET="\033[0m"

                  echo -e "''${BLUE_BOLD}User units:''${RESET}"
                  systemctl --user list-units --state=failed
                  echo -e "''${BLUE_BOLD}System units:''${RESET}"
                  systemctl list-units --state=failed

                  read -n 1 -s -r -p "Press any key to exit"
                '';
              in
              {
                hide-on-ok = false;
                format-ok = "SYSOK";
                format = "SYSF:{nr_failed}";
                system = true;
                user = true;
                on-click = "${lib.getExe pkgs.alacritty} --class alacritty-popup -e ${lib.getExe check-failing-units}";
              };
            "custom/separator" = {
              format = "﹏﹏﹏";
              nterval = "once";
              tooltip = false;
            };
          };
      };
    };
}
