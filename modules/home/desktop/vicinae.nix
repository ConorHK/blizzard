{
  flake.modules.homeManager.vicinae = { inputs, ... }: {
    imports = [
      inputs.vicinae.homeManagerModules.default
    ];

    wayland.windowManager.hyprland.settings.bind = [
      "SUPER, Space, exec, vicinae toggle"
    ];
    services.vicinae = {
      enable = true;
      autoStart = true;
    };
  };
}
