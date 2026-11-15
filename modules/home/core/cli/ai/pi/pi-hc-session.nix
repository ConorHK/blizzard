{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.hc-session = ./hc-session.ts;
  };
}
