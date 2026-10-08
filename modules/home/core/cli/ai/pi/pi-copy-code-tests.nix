{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.pi-copy-code =
        pkgs.runCommand "pi-copy-code-test" { nativeBuildInputs = [ pkgs.nodejs-slim_24 ]; }
          ''
            cp -r ${config.packages.pi-copy-code} copy-code
            cp ${./pi-copy-code-test.ts} copy-code.test.ts
            node --test copy-code.test.ts
            touch $out
          '';
    };
}
