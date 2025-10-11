{
  flake.modules.homeManager.core = {
    programs.fzf = {
      enable = true;
      defaultOptions = [
        "--height 40%"
        "--border"
      ];
      fileWidgetOptions = [
        "--preview 'head {}'"
      ];
      historyWidgetOptions = [
        "--sort"
      ];
    };
  };
}
