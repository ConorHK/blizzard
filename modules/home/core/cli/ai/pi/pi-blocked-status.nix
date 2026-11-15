{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.blocked-status = ./blocked-status.ts;
  };
}
