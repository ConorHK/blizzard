{ inputs, ... }:
{
  flake.wrappers.supersonic =
    { pkgs, wlib, ... }:
    let
      fonts = "${
        inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.creeper-ttf
      }/share/fonts/truetype";
      config = pkgs.replaceVars ./config.toml {
        regular = "${fonts}/creeper-regular.ttf";
        bold = "${fonts}/creeper-bold.ttf";
      };
      python = pkgs.python3.withPackages (p: [ p.tomli-w ]);
    in
    {
      imports = [ wlib.modules.default ];
      # Creeper is a 15px bitmap, so every text size is 15 or 30 to stay on its pixel grid.
      package = pkgs.supersonic.overrideAttrs (old: {
        patches = old.patches or [ ] ++ [ ./creeper-sizes.patch ];
      });
      # Without notify-send, track notifications fall back to ones that never expire.
      runtimePkgs = [ pkgs.libnotify ];
      # Supersonic rewrites config.toml on exit, so the managed keys are merged in at each start.
      runShell = [ "${python.interpreter} -I ${./merge.py} ${config} ${./blizzard.toml}" ];
    };
}
