{
  perSystem =
    { pkgs, ... }:
    let
      mod = ../../../../modules/home/desktop/herdr/pane-picker;
    in
    {
      checks.herdr-pane-picker =
        pkgs.runCommand "herdr-pane-picker-test"
          {
            nativeBuildInputs = [
              pkgs.nodejs-slim_24
              pkgs.python3
            ];
          }
          ''
            for part in fuzzy grep; do
              cp ${mod}/$part.js $part.mjs
            done
            cp ${./pane-picker-test.mjs} pane-picker.test.mjs
            node --test pane-picker.test.mjs

            cp ${mod}/screens.py screens.py
            cp ${./pane-picker-test.py} screens_test.py
            python3 screens_test.py
            touch $out
          '';
    };
}
