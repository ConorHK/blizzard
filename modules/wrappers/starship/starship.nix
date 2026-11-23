{
  flake.wrappers.starship =
    { pkgs, wlib, ... }:
    let
      configDir = builtins.path {
        path = ./config;
        name = "starship-config";
      };
    in
    {
      imports = [ wlib.modules.default ];
      package = pkgs.starship;
      # A default only: fish points STARSHIP_CONFIG at the jj prompt inside jj repos.
      envDefault.STARSHIP_CONFIG = "${configDir}/starship.toml";
      passthru = { inherit configDir; };
    };
}
