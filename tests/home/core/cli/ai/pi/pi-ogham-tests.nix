{ inputs, ... }:
{
  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      checks.pi-ogham =
        pkgs.runCommand "pi-ogham-test" { nativeBuildInputs = [ pkgs.nodejs-slim_24 ]; }
          ''
            cp -r ${config.packages.pi-ogham} ogham
            cp ${./pi-ogham-test.ts} ogham.test.ts
            # The picker imports pi-tui from pi itself.
            ln -s ${inputs.pi.packages.${system}.default}/lib/pi/node_modules node_modules
            export HOME=$PWD/home
            node --test ogham.test.ts
            touch $out
          '';
    };
}
