{
  flake.wrappers.dunst =
    {
      config,
      lib,
      pkgs,
      wlib,
      ...
    }:
    let
      categories = [
        "actions"
        "animations"
        "apps"
        "categories"
        "devices"
        "emblems"
        "emotes"
        "filesystem"
        "intl"
        "legacy"
        "mimetypes"
        "places"
        "status"
        "stock"
      ];
      roots = config.iconDirs ++ [
        pkgs.tela-icon-theme
        pkgs.hicolor-icon-theme
      ];
      iconPath = lib.concatStringsSep ":" (
        lib.concatMap (
          root:
          lib.concatMap (category: [
            "${root}/share/icons/Tela/32x32/${category}"
            "${root}/share/icons/hicolor/32x32/${category}"
          ]) categories
        ) roots
      );
    in
    {
      imports = [ wlib.modules.default ];

      options.iconDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "/run/current-system/sw" ];
        description = "Profiles searched for icons before the icon themes themselves.";
      };

      config = {
        package = pkgs.dunst;
        flags."-config" = pkgs.replaceVars ./dunstrc { inherit iconPath; };
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      wrappers.packages.dunst = !pkgs.stdenv.hostPlatform.isLinux;
    };
}
