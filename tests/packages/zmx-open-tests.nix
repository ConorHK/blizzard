{
  perSystem =
    { pkgs, ... }:
    {
      checks.zmx-open = pkgs.runCommand "zmx-open-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${./zmx_open_test.py} ${../../modules/packages/zmx-open.py}
        touch "$out"
      '';
    };
}
