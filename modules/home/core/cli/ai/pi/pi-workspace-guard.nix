{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.workspace-guard = ./workspace-guard.ts;
  };
}
