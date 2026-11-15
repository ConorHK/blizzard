{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.bash-highlight = ./bash-highlight.ts;
  };
}
