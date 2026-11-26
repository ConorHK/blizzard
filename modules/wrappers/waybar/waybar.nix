topLevel: {
  flake.wrappers.waybar =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      icon = cp: builtins.fromJSON ''"\u${cp}"'';
      alacritty = topLevel.config.flake.wrappers.alacritty.wrap { inherit pkgs; };
      jujutsu = topLevel.config.flake.wrappers.jujutsu.wrap { inherit pkgs; };
      main = {
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
        ]
        ++ config.extraModules
        ++ [
          "bluetooth"
          "network"
          "custom/separator"
          "systemd-failed-units"
          "custom/backup"
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
          format = "n:?";
          format-linked = "n:lnk";
          format-ethernet = "e:con";
          format-wifi = "w:con";
          format-disconnected = "n:dis";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          tooltip-format-ethernet = "{ifname}";
          tooltip-format-disconnected = "disconnected";
          on-click = "${lib.getExe alacritty} --class alacritty-popup -e ${pkgs.networkmanager}/bin/nmtui-connect";
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
            check-flake-updates = pkgs.writeShellApplication {
              name = "check-flake-updates";
              runtimeInputs = [
                jujutsu
                pkgs.coreutils
                pkgs.git
                pkgs.openssh
              ];
              bashOptions = [ ];
              text = builtins.readFile ./check-flake-updates.sh;
            };
            jj-status = pkgs.writeShellScriptBin "jj-status" ''
              cd "$HOME/repositories/blizzard" || exit 1
              ${lib.getExe jujutsu} git fetch --remote origin --branch main
              ${lib.getExe jujutsu} --no-pager log -r '@ | main@origin | ::main@origin ~ ::@ | ::@ ~ ::main@origin'
              read -n 1 -s -r -p "Press any key to exit"
            '';
          in
          {
            format = "{}";
            exec = "${lib.getExe check-flake-updates} $HOME/repositories/blizzard origin";
            exec-if = "test -d $HOME/repositories/blizzard/.jj";
            interval = 300;
            tooltip = true;
            on-click = "${lib.getExe alacritty} --class alacritty-popup -e ${lib.getExe jj-status}";
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
            on-click = "${lib.getExe alacritty} --class alacritty-popup -e ${lib.getExe check-failing-units}";
          };
        "custom/backup" =
          let
            check-backups = pkgs.writeShellApplication {
              name = "check-backups";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.jq
                pkgs.systemd
              ];
              text = builtins.readFile ./check-backups.sh;
            };
          in
          {
            format = "{}";
            exec = "${lib.getExe check-backups} /var/lib/restic-status";
            # Hosts without backups hide the module.
            exec-if = "test -d /var/lib/restic-status";
            interval = 60;
            tooltip = true;
            return-type = "json";
          };
        "custom/separator" = {
          format = "﹏﹏﹏";
          interval = "once";
          tooltip = false;
        };
      }
      // lib.optionalAttrs (config.output != null) { inherit (config) output; };
    in
    {
      imports = [ wlib.modules.default ];

      options = {
        extraModules = lib.mkOption {
          type = with lib.types; listOf str;
          default = [ ];
          description = "Sidebar modules placed below volume.";
        };
        output = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "DP-1";
          description = "Output that shows the bar. Unset shows it on every output.";
        };
      };

      config = {
        package = pkgs.waybar.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            # Class follows the real failed-unit count, not the managers' transient SystemState.
            substituteInPlace src/modules/systemd_failed_units.cpp \
              --replace-fail 'if (overall_state_ == "degraded") {' 'if (true) {' \
              --replace-fail 'RequestFailedUnits([this, done] { RequestFailedUnitsList(done); });' \
                             'RequestFailedUnits([this, done] { overall_state_ = nr_failed_ == 0 ? "ok" : "degraded"; RequestFailedUnitsList(done); });'
            # Custom modules pack their label at the start of a box, so it left-aligns in a vertical bar.
            substituteInPlace src/AIconLabel.cpp \
              --replace-fail 'event_box_.add(box_);' 'label_.set_hexpand(true); event_box_.add(box_);'
          '';
        });
        flags = {
          "--config" = pkgs.writeText "waybar-config.json" (builtins.toJSON [ main ]);
          "--style" = ./style.css;
        };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.waybar = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
