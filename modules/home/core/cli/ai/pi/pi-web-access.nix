{ config, ... }:
let
  inherit (config.flake.lib) mkPiExtension;
in
{
  flake.modules.homeManager.pi =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      ffmpeg = lib.getExe' pkgs.ffmpeg-headless;
      pi-web-access = mkPiExtension pkgs "pi-web-access" {
        # Video frame tools, pinned off PATH.
        postInstall = ''
          substituteInPlace $out/dist/index.js \
            --replace-fail 'execFileSync("yt-dlp", [' 'execFileSync("${lib.getExe pkgs.yt-dlp}", [' \
            --replace-fail 'execFileSync("ffmpeg", [' 'execFileSync("${ffmpeg "ffmpeg"}", [' \
            --replace-fail 'execFileSync2("ffmpeg", [' 'execFileSync2("${ffmpeg "ffmpeg"}", [' \
            --replace-fail 'execFileSync2("ffprobe", [' 'execFileSync2("${ffmpeg "ffprobe"}", ['
        '';
      };
    in
    {
      options.programs.pi.webAccess.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the pi-web-access package.";
      };

      config = lib.mkIf config.programs.pi.webAccess.enable {
        # Package entry: loads manifest extensions.
        programs.pi.settings.packages = [ "${pi-web-access}" ];
      };
    };
}
