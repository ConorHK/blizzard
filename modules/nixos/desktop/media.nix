{ config, ... }:
let
  inherit (config.flake) wrappers;
in
{
  flake.modules.nixos.desktop = {
    imports = [
      wrappers.mpv.install
      wrappers.supersonic.install
      wrappers.zathura.install
    ];
    wrappers = {
      mpv.enable = true;
      supersonic.enable = true;
      zathura.enable = true;
    };

    xdg.mime.defaultApplications."application/pdf" = "org.pwmt.zathura.desktop";
  };
}
