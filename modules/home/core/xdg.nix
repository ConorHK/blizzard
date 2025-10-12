{
  flake.modules.homeManager.xdg =
    { lib, config, ... }:
    {
      home.sessionVariables = {
        GTK2_RC_FILES = lib.mkForce "${config.xdg.configHome}/gtk-2.0/gtkrc";
      };

      xdg = {
        enable = true;
        cacheHome = config.home.homeDirectory + "/.local/cache";
        userDirs = {
          enable = true;
          createDirectories = true;

          desktop = lib.mkDefault "${config.home.homeDirectory}/desktop";
          documents = lib.mkDefault "${config.home.homeDirectory}/docs";
          download = lib.mkDefault "${config.home.homeDirectory}/dl";
          music = lib.mkDefault "${config.home.homeDirectory}/media/music";
          pictures = lib.mkDefault "${config.home.homeDirectory}/media/pictures";
          publicShare = null;
          templates = null;
          videos = lib.mkDefault "${config.home.homeDirectory}/media/videos";

          extraConfig = {
            XDG_SCREENSHOTS_DIR = "${config.home.homeDirectory}/media/pictures/screenshots";
            XDG_REPOSITORIES_DIR = "${config.home.homeDirectory}/repositories";
          };
    };
    };
    };
}
