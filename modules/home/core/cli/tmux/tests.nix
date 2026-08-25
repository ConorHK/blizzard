{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      homes = lib.filterAttrs (
        _: home: home.pkgs.stdenv.hostPlatform.system == system && home.config.programs.tmux.enable
      ) config.flake.homeConfigurations;

      # Named `nvim` so `pane_current_command` reports it, and logs the bytes it
      # is sent so the C-hjkl passthrough can be observed from outside. Puts the
      # terminal in raw mode like a real editor, or the keys would sit in the
      # line discipline waiting for a newline.
      fakeNvim = pkgs.writeCBin "nvim" ''
        #include <stdio.h>
        #include <termios.h>
        #include <unistd.h>

        int main(int argc, char **argv) {
          if (argc < 2) return 1;

          FILE *log = fopen(argv[1], "w");
          if (log == NULL) return 1;
          setvbuf(log, NULL, _IONBF, 0);

          struct termios raw;
          if (tcgetattr(0, &raw) == 0) {
            cfmakeraw(&raw);
            tcsetattr(0, TCSANOW, &raw);
          }

          unsigned char byte;
          while (read(0, &byte, 1) == 1) fprintf(log, "%02x\n", byte);
          return 0;
        }
      '';

      fakeEditor = pkgs.writeShellScript "fake-editor" ''
        cp -- "$1" "$1.opened"
      '';

      driveKeys = pkgs.writers.writePython3Bin "drive-keys" {
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./drive-keys.py);

      mkChecks =
        name: runner: arguments:
        lib.mapAttrs' (
          home: hm:
          lib.nameValuePair "tmux-${name}-${home}" (
            pkgs.runCommand "tmux-${name}-${home}"
              {
                nativeBuildInputs = [
                  hm.config.programs.tmux.package
                  pkgs.ncurses
                ];
              }
              ''
                export HOME=$PWD TMUX_TMPDIR=$PWD
                export TERMINFO_DIRS=${pkgs.ncurses}/share/terminfo
                ${runner} ${lib.escapeShellArgs (arguments hm)}
                touch $out
              ''
          )
        ) homes;

      conf = hm: "${hm.config.xdg.configFile."tmux/tmux.conf".source}";

      sesh =
        hm:
        lib.getExe (
          lib.findFirst (
            drv: (drv.name or "") == "sesh"
          ) (throw "the tmux module must put a session picker named sesh on the path") hm.config.home.packages
        );
    in
    {
      checks =
        mkChecks "config" (pkgs.writeShellScript "check-tmux-config" (builtins.readFile ./check-config.sh))
          (hm: [
            (conf hm)
            (lib.getExe fakeNvim)
            "${fakeEditor}"
            (sesh hm)
          ])
        // mkChecks "keys" (lib.getExe driveKeys) (hm: [
          (conf hm)
          (lib.getExe fakeNvim)
          (sesh hm)
        ]);
    };
}
