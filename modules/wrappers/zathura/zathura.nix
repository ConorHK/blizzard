{
  flake.wrappers.zathura =
    {
      lib,
      pkgs,
      wlib,
      ...
    }:
    {
      imports = [ wlib.modules.default ];
      package = pkgs.zathura;
      flags."--config-dir" = builtins.path {
        path = ./config;
        name = "zathura-config";
      };
      wrapperVariants.zathura-sandbox = lib.mkIf pkgs.stdenv.hostPlatform.isLinux { };
    };
}
