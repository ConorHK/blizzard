topLevel: {
  flake.modules.homeManager.herdr-web-ui =
    { lib, pkgs, ... }:
    let
      package = topLevel.inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.herdr-web-ui;
    in
    {
      # Herdr rewrites plugins.json, so link it.
      home.activation.herdrWebUi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run --quiet ${lib.getExe pkgs.herdr} plugin link ${package}/share/herdr-web-ui \
          || warnEcho "herdr plugin link failed for herdr-web-ui"
      '';
    };
}
