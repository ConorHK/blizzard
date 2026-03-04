{
  flake.modules.homeManager.cnvim =
    {
      inputs,
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = config.programs.cnvim;
      packages = inputs.cnvim.packages.${pkgs.system};
    in
    {
      options.programs.cnvim.variant = lib.mkOption {
        type = lib.types.str;
        default = "nightly";
        description = "Which cnvim package output to install";
      };

      config = {
        home = {
          packages = [ packages.${cfg.variant} ];
          shellAliases.vim = "nvim";
          sessionVariables.EDITOR = "nvim";
        };
      };
    };
}
