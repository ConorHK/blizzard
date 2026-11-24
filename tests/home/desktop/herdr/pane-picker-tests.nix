{
  perSystem =
    { pkgs, ... }:
    {
      checks.herdr-pane-picker =
        pkgs.runCommand "herdr-pane-picker-test" { nativeBuildInputs = [ pkgs.nodejs-slim_24 ]; }
          ''
            cp ${../../../../modules/home/desktop/herdr/pane-picker/fuzzy.js} fuzzy.mjs
            cp ${./pane-picker-test.mjs} fuzzy.test.mjs
            node --test fuzzy.test.mjs
            touch $out
          '';
    };
}
