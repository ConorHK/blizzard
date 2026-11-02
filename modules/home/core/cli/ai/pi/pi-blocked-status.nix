{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.blockedStatus.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Report ask_user waits to herdr as blocked.";
      };

      config = lib.mkIf config.programs.pi.blockedStatus.enable {
        programs.pi.extensions.blocked-status = ./blocked-status.ts;
      };
    };
}
