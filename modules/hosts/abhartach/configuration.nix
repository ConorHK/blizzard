{
  flake.modules.nixos."nixosConfigurations/abhartach" =
    { config, pkgs, ... }:
    let
      # Quiet-gaming tuning for the Radeon RX 7900 XT. Lowering the power
      # cap (default 282W) cuts heat at the source so the firmware fan
      # curve ramps less; the small undervolt claws back the lost
      # performance. Fan control is left to firmware so zero-RPM idle
      # (silent) is preserved. GPU key comes from `lact cli list`.
      lactConfig = (pkgs.formats.yaml { }).generate "lact-config.yaml" {
        version = 6;
        daemon = {
          log_level = "info";
          admin_group = "wheel";
          disable_clocks_cleanup = false;
        };
        apply_settings_timer = 5;
        current_profile = null;
        auto_switch_profiles = false;
        gpus."1002:744C-1458:240C-0000:03:00.0" = {
          fan_control_enabled = false;
          power_cap = 255.0;
          voltage_offset = -30;
          # VRAM clock switching flickers the 144Hz LG.
          performance_level = "manual";
          power_states.memory_clock = [ 3 ];
        };
      };

      hyprctl = "${config.programs.hyprland.package}/bin/hyprctl";

      # Pick the largest DP-1 mode within the client's size and FPS, then drop DP-2 so the cursor stays on the stream.
      streamStart = pkgs.writeShellScript "sunshine-stream-start" ''
        mode=$(${hyprctl} monitors -j | ${pkgs.jq}/bin/jq -r \
          --argjson w "$SUNSHINE_CLIENT_WIDTH" --argjson h "$SUNSHINE_CLIENT_HEIGHT" --argjson f "$SUNSHINE_CLIENT_FPS" '
            .[] | select(.name == "DP-1") | .availableModes
            | map(capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz") | {w: (.w | tonumber), h: (.h | tonumber), r: (.r | tonumber)})
            | map(select(.w <= $w and .h <= $h and .r <= $f + 1))
            | max_by([.w * .h, .r]) // empty
            | "\(.w)x\(.h)@\(.r)"')
        [ -n "$mode" ] || mode=preferred
        ${hyprctl} eval "hl.monitor({ output = \"DP-1\", mode = \"$mode\", position = \"0x0\", scale = \"1\" })"
        ${hyprctl} eval 'hl.monitor({ output = "DP-2", disabled = true })'
      '';
      streamStop = pkgs.writeShellScript "sunshine-stream-stop" ''
        ${hyprctl} reload
      '';
      matchClient = {
        do = "${streamStart}";
        undo = "${streamStop}";
      };
    in
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBeGvQMzAFPToh87kRuK4ogdA3OCFXIiEPuohfcLPWx";

      age.secrets = {
        home-backup-password = {
          rekeyFile = ./secrets/home-backup-password.age;
          generator.script = "alnum";
        };
        # B2 key scoped to the bucket.
        home-backup-b2.rekeyFile = ./secrets/home-backup-b2.age;
      };

      blizzard = {
        bitbang.shareMembers = [ "goose" ];
        backup.jobs.home = {
          passwordFile = config.age.secrets.home-backup-password.path;
          environmentFile = config.age.secrets.home-backup-b2.path;
        };
      };

      networking = {
        hostName = "abhartach";
        ipv4.address = "192.168.0.38";
        # Lets Moonlight wake the PC.
        interfaces.enp13s0.wakeOnLan.enable = true;
      };

      services.sunshine = {
        settings.output_name = "DP-1";
        applications.apps = [
          {
            name = "Desktop";
            image-path = "desktop.png";
            prep-cmd = [ matchClient ];
          }
          {
            name = "Steam Big Picture";
            image-path = "steam.png";
            prep-cmd = [
              matchClient
              {
                do = "";
                undo = "${pkgs.util-linux}/bin/setsid steam steam://close/bigpicture";
              }
            ];
            detached = [ "${pkgs.util-linux}/bin/setsid steam steam://open/bigpicture" ];
          }
        ];
      };

      # venus advertises our LAN range; keep LAN local.
      services.tailscale.extraSetFlags = [ "--accept-routes=false" ];

      security.sudo.wheelNeedsPassword = false;

      # LACT rewrites its config at runtime, so seed a writable copy each
      # rebuild rather than a read-only /nix/store symlink. This repo is
      # the source of truth; GUI edits persist only until the next switch.
      system.activationScripts.lactConfig.text = ''
        install -Dm644 ${lactConfig} /etc/lact/config.yaml
      '';
      systemd.services.lactd.restartTriggers = [ lactConfig ];

      system = {
        stateVersion = "25.05";
        autoUpgrade.enable = false;
      };
    };
}
