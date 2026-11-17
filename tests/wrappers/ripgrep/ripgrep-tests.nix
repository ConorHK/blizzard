{
  perSystem =
    {
      lib,
      pkgs,
      self',
      ...
    }:
    {
      checks.ripgrep = pkgs.runCommand "ripgrep-test" { } ''
        echo needle > hay.txt
        ${lib.getExe self'.packages.ripgrep} --color=always --with-filename needle hay.txt |
          grep --quiet 'file://.*hay\.txt#1'
        touch "$out"
      '';
    };
}
