{
  flake.modules.homeManager.core = {
    programs.less.enable = true;
    home.sessionVariables.LESSHISTFILE = "$XDG_CACHE_HOME/less/history";
  };
}
