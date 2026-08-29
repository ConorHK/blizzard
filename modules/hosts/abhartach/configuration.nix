{
  flake.modules.nixos."nixosConfigurations/abhartach" =
    { pkgs, ... }:
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
        };
      };
    in
    {
      age.rekey.hostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBeGvQMzAFPToh87kRuK4ogdA3OCFXIiEPuohfcLPWx";

      blizzard.bitbang.shareMembers = [ "goose" ];

      networking.hostName = "abhartach";
      networking.ipv4.address = "192.168.0.38";

      security.sudo.wheelNeedsPassword = false;
      programs.nix-ld.enable = true;

      # LACT rewrites its config at runtime, so seed a writable copy each
      # rebuild rather than a read-only /nix/store symlink. This repo is
      # the source of truth; GUI edits persist only until the next switch.
      system.activationScripts.lactConfig.text = ''
        install -Dm644 ${lactConfig} /etc/lact/config.yaml
      '';

      system = {
        stateVersion = "25.05";
        autoUpgrade.enable = false;
      };
    };
}
