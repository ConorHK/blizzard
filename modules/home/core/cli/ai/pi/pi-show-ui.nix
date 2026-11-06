{
  flake.modules.homeManager.pi =
    { config, lib, ... }:
    {
      options.programs.pi.showUi.enable =
        lib.mkEnableOption "the show_ui tool, which draws in Herdr's canvas sidebar";

      config = lib.mkIf config.programs.pi.showUi.enable {
        programs.pi.extensions.show-ui = ./show-ui.ts;
      };
    };
}
