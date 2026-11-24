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

        wrappers.fish.extraConfig = "alias vim nvim";

        home = {
          packages = [ cnvim ];
          sessionVariables.EDITOR = "nvim";
        };
      };
    };
}
