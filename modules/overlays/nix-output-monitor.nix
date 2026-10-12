# TEMPORARY: nom 2.2.0 errors on unknown activity types.
# Determinate Nix tags spans with type 10113.
# See maralorn/nix-output-monitor#309.
# --replace-fail breaks once upstream fixes it.
{
  flake.overlays.nix-output-monitor = _final: prev: {
    nix-output-monitor = prev.nix-output-monitor.override {
      extraComposeFunctions = [
        (prev.haskell.lib.compose.overrideCabal (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace lib/NOM/Parser/JSON.hs \
              --replace-fail 'other -> fail ("invalid activity type: " <> show other)' \
                '_ -> pure UnknownType' \
              --replace-fail 'other -> fail ("invalid activity result type: " <> show other)' \
                '_ -> pure (FileLinked 0 0)'
          '';
        }))
      ];
    };
  };
}
