{
  hyprland.lua.kitty = ''
    hl.bind("SUPER + Return", hl.dsp.exec_cmd("uwsm app -- kitty"))
  '';

  flake.modules.homeManager.kitty = {
    xdg.configFile = {
      "kitty/open-actions.conf".source = ./open-actions.conf;
      "kitty/remote-pane.py".source = ./remote-pane.py;
      "kitty/save-session.py".source = ./save-session.py;
      "kitty/session-autosave.py".source = ./session-autosave.py;
      "kitty/zmx-clean.py".source = ./zmx-clean.py;
      "kitty/zmx-close.py".source = ./zmx-close.py;
      "kitty/zmx-host.py".source = ./zmx-host.py;
      "kitty/zmx-rename.py".source = ./zmx-rename.py;
      "kitty/zmx_kitten.py".source = ./zmx_kitten.py;
    };

    programs.kitty = {
      enable = true;
      extraConfig = builtins.readFile ./kitty.conf;
    };
  };
}
