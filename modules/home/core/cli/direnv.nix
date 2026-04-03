{
  flake.modules.homeManager.direnv = _: {
    programs.direnv = {
      enable = true;
      enableFishIntegration = true;
      nix-direnv.enable = true;
    };
  };
}
