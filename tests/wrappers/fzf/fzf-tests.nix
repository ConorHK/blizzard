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
      checks.fzf = pkgs.runCommand "fzf-test" { } ''
        export TERM=xterm-256color
        # 175;135;95 is #af875f, the prompt colour in fzfrc.
        ${ptyExpect pkgs} '38;2;175;135;95' ${lib.getExe self'.packages.fzf}
        touch "$out"
      '';
    };
}
