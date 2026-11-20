{
  flake.wrappers.bat =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      configDir = builtins.path {
        path = ./config;
        name = "bat-config";
      };
      # Bat loads themes from a compiled cache, never from the theme files.
      cache = pkgs.runCommand "bat-cache" { } ''
        ${lib.getExe config.package} cache --build --source ${configDir} --target $out
      '';
    in
    {
      imports = [ wlib.modules.default ];
      package = pkgs.bat;
      env = {
        BAT_CONFIG_DIR = "${configDir}";
        BAT_CACHE_PATH = "${cache}";
      };
    };
}
