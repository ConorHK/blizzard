{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.hc-fork = ./hc-fork.ts;
  };
}
