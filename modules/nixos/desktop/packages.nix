{
  flake.modules.nixos.desktop =
    { lib, pkgs, ... }:
    {
      environment.systemPackages = lib.attrValues {
        inherit (pkgs)
          ffmpeg
          ffmpegthumbnailer
          gthumb
          imagemagick
          vlc
          ;
      };
    };
}
