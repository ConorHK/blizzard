{
  # A telescope-style picker over every pane, with the chosen pane's screen beside the list.
  flake.modules.homeManager.herdr =
    { config, ... }:
    {
      xdg.configFile = config.lib.herdr.modFiles "pane-picker" ./pane-picker;

      programs.herdr-app.keys.global."alt-g" = "mod.open:pane-picker";
    };
}
