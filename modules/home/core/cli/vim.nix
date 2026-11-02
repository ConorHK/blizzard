{ inputs, ... }:
{
  flake.modules.homeManager.cnvim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cnvim = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.cnvim;
    in
    {
      options.programs.cnvim.extraLua = lib.mkOption {
        type = lib.types.lines;
        default = "";
        example = ''vim.filetype.add({ filename = { Config = "conf" } })'';
        description = "Lua that cnvim runs after its own config, for one machine.";
      };

      config = {
        xdg.configFile."cnvim/local.lua" = lib.mkIf (config.programs.cnvim.extraLua != "") {
          text = config.programs.cnvim.extraLua;
        };

        home = {
          packages = [ cnvim ];
          shellAliases.vim = "nvim";
          sessionVariables.EDITOR = "nvim";
        };

        # The herdr-nvim sidebar runs this nvim.
        xdg.configFile."herdr-nvim/config.toml".source =
          (pkgs.formats.toml { }).generate "herdr-nvim.toml"
            {
              sidebar = {
                nvim_bin = lib.getExe' cnvim "nvim";
                # cnvim enables ui2 for the sidebar.
                nvim_env = [ "HERDR_NVIM_SIDEBAR=1" ];
              };
            };
      };
    };
}
