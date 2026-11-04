{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.hcSession.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Label herdr-core terminals with pi's session file.";
      };

      config = lib.mkIf config.programs.pi.hcSession.enable {
        programs.pi.extensions.hc-session = ./hc-session.ts;
      };
    };
}
