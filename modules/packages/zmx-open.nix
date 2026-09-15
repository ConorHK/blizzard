{
  perSystem =
    { pkgs, ... }:
    {
      # python stdlib only; zmx is co-installed by the caller modules.
      packages.zmx-open =
        (pkgs.writers.writePython3Bin "zmx-open" { } (builtins.readFile ./zmx-open.py)).overrideAttrs
          (_: {
            meta = {
              description = "Open or reattach a zmx session for a kitty pane";
              mainProgram = "zmx-open";
            };
          });
    };
}
