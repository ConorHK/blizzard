{
  hyprland.lua.kitty = ''
    hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("uwsm app -- kitty"))
  '';

  flake.modules.homeManager.kitty = {
    xdg.configFile = {
      "kitty/open-actions.conf".source = ./open-actions.conf;
      "kitty/remote-pane.py".source = ./remote-pane.py;
    };

    programs.kitty = {
      enable = true;
      extraConfig = builtins.readFile ./kitty.conf;
    };
  };
}
