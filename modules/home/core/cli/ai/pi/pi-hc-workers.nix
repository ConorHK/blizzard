{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.hcWorkers.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the hc_worker tool for herdr-app workers.";
      };

      config = lib.mkIf config.programs.pi.hcWorkers.enable {
        programs.pi.extensions.hc-workers = ./hc-workers.ts;
      };
    };
}
