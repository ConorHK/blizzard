{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.pi-ttsr =
        pkgs.runCommand "pi-ttsr-test"
          {
            nativeBuildInputs = [ pkgs.nodejs-slim_24 ];
            PI_TTSR_AST_GREP = pkgs.lib.getExe pkgs.ast-grep;
          }
          ''
            cp -r ${config.packages.pi-ttsr} ttsr
            cp ${./pi-ttsr-test.ts} ttsr.test.ts
            node --test ttsr.test.ts
            touch $out
          '';
    };
}
