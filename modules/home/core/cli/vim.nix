{
  flake.modules.homeManager.cnvim = 
    { inputs, pkgs, ... }:
    {
    home = {
      packages = [ inputs.cnvim.packages.${pkgs.system}.nightly ];
      shellAliases.vim = "nvim";
      sessionVariables.EDITOR = "nvim";
    };
  };
}
