{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.sudoPw.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the sudo-pw extension.";
      };

      config = lib.mkIf config.programs.pi.sudoPw.enable {
        programs.pi.extensions.sudo-pw = ./sudo-pw.ts;
      };
    };
}
