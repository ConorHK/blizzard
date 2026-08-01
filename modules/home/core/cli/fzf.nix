{
  flake.modules.homeManager.core = {
    programs.fzf = {
      enable = true;
      defaultOptions = [
        "--height 40%"
        "--border"
      ];
      fileWidget.options = [
        "--preview 'head {}'"
      ];
      historyWidget.options = [
        "--sort"
      ];
    };
  };
}
