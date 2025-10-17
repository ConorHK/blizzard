{
  flake.modules.homeManager.hyprland =
    { lib, ... }:
    {
      wayland.windowManager.hyprland.settings = {
        monitor = lib.mkDefault [ ", highrr, auto, 1, vrr, 3" ];

        xwayland = {
          enabled = true;
          force_zero_scaling = true;
        };

        general = {
          gaps_in = 10;
          gaps_out = 8;
          border_size = 2;
          "col.active_border" = lib.mkForce "0xFFAF875F";
          resize_on_border = true;
        };

        input = {
          follow_mouse = 1;

          repeat_delay = 400;
          repeat_rate = 30;

          kb_layout = lib.mkDefault "us";

          touchpad = {
            clickfinger_behavior = true;
            drag_lock = true;
            natural_scroll = true;
            scroll_factor = 0.7;
          };
        };

        gesture = [
          "3, horizontal, workspace"
        ];

        animations = {
          bezier = [ "material_decelerate, 0.05, 0.7, 0.1, 1" ];

          animation = [
            "border    , 1, 2, material_decelerate"
            "fade      , 1, 2, material_decelerate"
            "layers    , 1, 2, material_decelerate"
            "windows   , 1, 2, material_decelerate, popin 80%"
            "workspaces, 1, 2, material_decelerate, slidevert"
          ];
        };

        layerrule = [
          "noanim, selection"
        ];

        misc = {
          animate_manual_resizes = true;

          disable_hyprland_logo = true;
          disable_splash_rendering = true;

          key_press_enables_dpms = true;
          mouse_move_enables_dpms = true;
        };

        cursor = {
          hide_on_key_press = true;
          inactive_timeout = 10;
          no_warps = true;
        };

        dwindle = {
          preserve_split = true;
          smart_resizing = true;
        };

        ecosystem = {
          no_update_news = true;
          no_donation_nag = true;
          enforce_permissions = false;
        };
      };
    };
}
