{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.herdrName.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Name pi sessions after their herdr space, tab and ogham task.";
      };

      config = lib.mkIf config.programs.pi.herdrName.enable {
        programs.pi.extensions.herdr-name = ./herdr-name.ts;
      };
    };
}
