{
  flake.wrappers.vicinae =
    { pkgs, wlib, ... }:
    let
      hyprLaunch = pkgs.writeShellScriptBin "hypr-launch" ''
        # Relaunch via Hyprland so the exec dispatcher mints a fresh initial-workspace token.
        if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -z "$_HYPR_LAUNCH_DISPATCHED" ]; then
          cmd=$(printf '%q ' "$0" "$@")
          exec hyprctl dispatch "hl.dsp.exec_cmd([==[_HYPR_LAUNCH_DISPATCHED=1 exec $cmd]==])"
        fi

        exec uwsm app -- "$@"
      '';
    in
    {
      imports = [ wlib.modules.default ];
      package = pkgs.vicinae;
      # Overrides leave settings.json to Vicinae, which writes its own changes there.
      env.VICINAE_OVERRIDES = pkgs.writeText "vicinae-overrides.json" (

        builtins.toJSON {
          providers = {
            applications.preferences.launchPrefix = "${hyprLaunch}/bin/hypr-launch";
            "@samlinville/tailscale".preferences.tailscalePath = "/run/current-system/sw/bin/tailscale";
            "@gebeto/translate".preferences.lang2 = "es";
          };
          pop_to_root_on_close = true;
          close_on_focus_loss = true;
          escape_key_behavior = "navigate_back";
          launcher_window = {
            opacity = 1;
            layer_shell = {
              keyboard_interactivity = "exclusive";
              # Vicinae defaults to the 'top' layer, which Hyprland renders
              # *below* fullscreen windows - so fullscreen games hide the
              # launcher. 'overlay' renders above fullscreen.
              layer = "overlay";
            };
          };
        }
      );
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.vicinae = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
