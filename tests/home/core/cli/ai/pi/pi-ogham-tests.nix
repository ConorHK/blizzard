{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.pi-ogham =
        pkgs.runCommand "pi-ogham-test" { nativeBuildInputs = [ pkgs.nodejs-slim_24 ]; }
          ''
            cp -r ${config.packages.pi-ogham} ogham
            cp ${./pi-ogham-test.ts} ogham.test.ts
            node --test ogham.test.ts
            touch $out
          '';
    };
}
