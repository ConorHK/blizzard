{ config, ... }:
{
  flake.modules.homeManager.zathura = {
    imports = [ config.flake.wrappers.zathura.install ];
    wrappers.zathura.enable = true;

    xdg.mimeApps.defaultApplications = {
      "application/pdf" = [ "org.pwmt.zathura.desktop" ];
    };
  };
}
