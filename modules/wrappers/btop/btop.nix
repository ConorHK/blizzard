{
  flake.wrappers.btop =
    {
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];
      package = lib.mkDefault pkgs.btop;
      flags = {
        "--config" = ./btop.conf;
        "--themes-dir" = builtins.path {
          path = ./themes;
          name = "btop-themes";
        };
      };
    };
}
