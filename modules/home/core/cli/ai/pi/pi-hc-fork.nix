{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.hcFork.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open /fork and /clone in a new herdr-app pane.";
      };

      config = lib.mkIf config.programs.pi.hcFork.enable {
        programs.pi.extensions.hc-fork = ./hc-fork.ts;
      };
    };
}
