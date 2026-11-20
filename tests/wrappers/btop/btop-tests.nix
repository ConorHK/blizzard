{ config, ... }:
let
  inherit (config.flake.testSupport) ptyExpect;
in
{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.btop = pkgs.runCommand "btop-test" { } ''
        export HOME=$TMPDIR TERM=xterm-256color
        # 28;28;28 is #1c1c1c, the background in the wrapped theme.
        ${ptyExpect pkgs} '48;2;28;28;28' ${lib.getExe self'.packages.btop} --force-utf
        touch "$out"
      '';
    };
}
