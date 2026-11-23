{ config, ... }:
{
  hyprland.lua.alacritty = ''
    hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("uwsm app -- alacritty"))
    hl.window_rule({ match = { class = "alacritty-popup" }, float = true })
    hl.window_rule({ match = { class = "alacritty-popup" }, center = true })
  '';

  flake.modules.nixos.desktop = {
    imports = [ config.flake.wrappers.alacritty.install ];
    wrappers.alacritty.enable = true;
  };
}
