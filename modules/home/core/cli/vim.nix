{ inputs, ... }:
{
  flake.modules.homeManager.cnvim =
    { pkgs, ... }:
    {
      config.home = {
        packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.cnvim ];
        shellAliases.vim = "nvim";
        sessionVariables.EDITOR = "nvim";
      };
    };
}
