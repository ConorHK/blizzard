{
  flake.wrappers.hyprlock =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];

      options.monitor = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "DP-1";
        description = "Output that shows the password field. Empty shows it on every output.";
      };

      config = {
        package = pkgs.hyprlock;
        flags."--config" = pkgs.replaceVars ./hyprlock.conf { inherit (config) monitor; };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.hyprlock = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
