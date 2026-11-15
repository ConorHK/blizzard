{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.hc-workers = ./hc-workers.ts;
  };
}
