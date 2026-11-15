{
  flake.modules.homeManager.pi = {
    programs.pi.extensions.sudo-pw = ./sudo-pw.ts;
  };
}
