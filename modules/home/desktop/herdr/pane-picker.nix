{ inputs, ... }:
{
  # A telescope-style picker over every pane: by name, or by the text on its screen and in its
  # history, with the chosen pane's screen in its own colors beside the list.
  flake.modules.homeManager.herdr =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (inputs.self.packages.${pkgs.stdenv.hostPlatform.system}) herdr-core;

      # hc attach wants a tty, which a mod cannot give it.
      screens = pkgs.writers.writePython3 "herdr-pane-screens" { flakeIgnore = [ "E501" ]; } (
        builtins.replaceStrings [ "@hc@" ] [ (lib.getExe herdr-core) ] (
          builtins.readFile ./pane-picker/screens.py
        )
      );
      # mod.open hands a mod no props, so the helper's path is written into its source.
      source = pkgs.runCommand "herdr-pane-picker-source" { } ''
        cp -r --no-preserve=mode ${./pane-picker} $out
        echo 'export const SCREENS = ${builtins.toJSON "${screens}"};' > $out/tools.js
      '';
    in
    {
      xdg.configFile = config.lib.herdr.modFiles "pane-picker" source;

      programs.herdr-app.keys.global."alt-g" = "mod.open:pane-picker";
    };
}
