{
  perSystem =
    { pkgs, ... }:
    {
      checks.zmx-switch = pkgs.runCommand "zmx-switch-test" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        mkdir kitty
        cp ${../../../../modules/home/desktop/kitty/zmx-switch.py} kitty/zmx-switch.py
        cp ${../../../../modules/home/desktop/kitty/zmx_kitten.py} kitty/zmx_kitten.py
        python3 ${./zmx_switch_test.py} kitty
        touch "$out"
      '';
    };
}
