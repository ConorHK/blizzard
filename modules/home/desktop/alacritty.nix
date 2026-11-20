{ config, ... }:
{
  hyprland.lua.alacritty = ''
    hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("uwsm app -- alacritty"))
    hl.window_rule({ match = { class = "alacritty-popup" }, float = true })
    hl.window_rule({ match = { class = "alacritty-popup" }, center = true })
  '';

  flake.modules.homeManager.alacritty = {
    imports = [ config.flake.wrappers.alacritty.install ];
    wrappers.alacritty.enable = true;
  };
}
