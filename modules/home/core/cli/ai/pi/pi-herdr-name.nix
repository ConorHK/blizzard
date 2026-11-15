{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.herdr-name = ./herdr-name.ts;
  };
}
