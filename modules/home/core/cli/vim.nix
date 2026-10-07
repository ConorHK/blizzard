{ inputs, ... }:
{
  flake.modules.homeManager.cnvim =
    { lib, pkgs, ... }:
    let
      cnvim = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.cnvim;
    in
    {
      config = {
        home = {
          packages = [ cnvim ];
          shellAliases.vim = "nvim";
          sessionVariables.EDITOR = "nvim";
        };

        # The herdr-nvim sidebar runs this nvim.
        xdg.configFile."herdr-nvim/config.toml".source =
          (pkgs.formats.toml { }).generate "herdr-nvim.toml"
            {
              sidebar.nvim_bin = lib.getExe' cnvim "nvim";
            };
      };
    };
}
