{
  flake.modules.homeManager.core = {
    programs.ripgrep = {
      enable = true;
      # OSC-8 links kitty can open at the match line.
      arguments = [ "--hyperlink-format=kitty" ];
    };
  };
}
