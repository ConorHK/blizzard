{ inputs, ... }:
{
  flake.modules.homeManager.pi-zvec-grep =
    { pkgs, ... }:
    {
      # Directory extension: index.ts + src/, vendored from
      # github.com/MikkelKappelPersson/pi-zvec-grep v0.3.1.
      programs.pi.extensionDirs.zvec-grep = ./zvec-grep;

      # zg must be on PATH; the extension shells out to it.
      home.packages = [
        (inputs.blizzard or inputs.self).packages.${pkgs.stdenv.hostPlatform.system}.zvec-grep
      ];
    };
}
