{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.tab-name = ./tab-name.ts;
  };
}
