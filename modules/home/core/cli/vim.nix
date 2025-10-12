{
  flake.modules.homeManager.core = {
    home = {
      shellAliases.vim = "nvim";
      sessionVariables.EDITOR = "nvim";
    };
  };
}
