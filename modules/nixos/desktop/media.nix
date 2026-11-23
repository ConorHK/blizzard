{ config, ... }:
let
  inherit (config.flake) wrappers;
in
{
  flake.modules.nixos.desktop = {
    imports = [
      wrappers.mpv.install
      wrappers.zathura.install
    ];
    wrappers = {
      mpv.enable = true;
      zathura.enable = true;
    };

    xdg.mime.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  };
}
