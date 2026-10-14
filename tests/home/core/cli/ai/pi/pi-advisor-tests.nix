{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.pi-advisor =
        pkgs.runCommand "pi-advisor-test" { nativeBuildInputs = [ pkgs.nodejs-slim_24 ]; }
          ''
            cp -r ${config.packages.pi-advisor} advisor
            cp ${./pi-advisor-test.ts} advisor.test.ts
            node --test advisor.test.ts
            touch $out
          '';
    };
}
