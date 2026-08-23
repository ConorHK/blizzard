{
  flake.modules.homeManager.waybar =
    { lib, pkgs, ... }:
    let
      icon = cp: builtins.fromJSON ''"\u${cp}"'';
    in
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
        # This Hyprland parses IPC dispatches as Lua, so waybar's legacy dispatch strings never fire.
        package = pkgs.waybar.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace src/modules/hyprland/workspace.cpp \
              --replace-fail '"dispatch focusworkspaceoncurrentmonitor " + std::to_string(id())' \
                             '"dispatch hl.dsp.focus({workspace = " + std::to_string(id()) + ", on_current_monitor = true})"' \
              --replace-fail '"dispatch workspace " + std::to_string(id())' \
                             '"dispatch hl.dsp.focus({workspace = " + std::to_string(id()) + "})"' \
              --replace-fail '"dispatch focusworkspaceoncurrentmonitor name:" + name()' \
                             '"dispatch hl.dsp.focus({workspace = \"name:" + name() + "\", on_current_monitor = true})"' \
              --replace-fail '"dispatch workspace name:" + name()' \
                             '"dispatch hl.dsp.focus({workspace = \"name:" + name() + "\"})"' \
              --replace-fail '"dispatch togglespecialworkspace " + name()' \
                             '"dispatch hl.dsp.workspace.toggle_special(\"" + name() + "\")"' \
              --replace-fail '"dispatch togglespecialworkspace"' \
                             '"dispatch hl.dsp.workspace.toggle_special()"'
            # Class follows the real failed-unit count, not the managers' transient SystemState.
            substituteInPlace src/modules/systemd_failed_units.cpp \
              --replace-fail 'if (overall_state == "degraded") RequestFailedUnits();' \
                             'RequestFailedUnits(); overall_state = nr_failed == 0 ? "ok" : "degraded";'
          '';
        });
        style = builtins.readFile ./style.css;
        settings.main = {
          name = "sidebar";
          reload_style_on_change = true;
          layer = "top";
          position = "left";
          spacing = 5;
          modules-left = [
            "clock"
          ];
          modules-center = [ "hyprland/workspaces" ];
          modules-right = [
            "privacy"
            "wireplumber"
            "bluetooth"
            "network"
            "custom/separator"
            "systemd-failed-units"
            "custom/system-up-to-date"
          ];
          "hyprland/workspaces" = {
            disable-scroll = true;
            format = "{icon}";
            format-icons = {
              active = "•";
              default = "•";
            };
            sort-by-number = true;
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
            format = "{icon}{volume}";
            format-icons = [
              (icon "E04E")
              (icon "E053")
              (icon "E050")
            ];
            format-muted = "${icon "E04F"}{volume}";
            max-volume = 100;
            scroll-step = 5;
            on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            on-click-right = "${lib.getExe pkgs.pwvucontrol}";
            tooltip-format = "{node_name}";
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
          backlight = {
            format = "l:{percent}%";
          };
          bluetooth = {
            format = "bt:on";
            format-off = "bt:off";
            format-disabled = "bt:dis";
            format-connected = "bt:{num_connections}";
            tooltip-format = "{controller_alias}";
            tooltip-format-connected = "{device_enumerate}";
            on-click = lib.getExe' pkgs.blueman "blueman-manager";
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
            interval = "once";
            tooltip = false;
          };
        };
      };
    };
}
