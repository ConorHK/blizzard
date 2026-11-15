{
  inputs,
  config,
  ...
}:
{
  nixpkgs.allowedUnfreePackages = [ "smartyank.nvim" ];

  perSystem =
    {
      system,
      pkgs,
      ...
    }:
    let
      # perSystem pkgs carries no unfree predicate; use the central allowlist.
      unfreePkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfreePredicate = config.flake.lib.allowUnfreePredicate;
      };
    in
    {
      packages.cnvim = unfreePkgs.callPackage ./cnvim/_package.nix {
        neovim-unwrapped = inputs.neovim-nightly-overlay.packages.${system}.neovim;
        # nixpkgs sets AWS_LC_SYS_USE_SYSTEM for all Rust builds but tectonic lacks aws-lc.
        tectonic = unfreePkgs.tectonic.override {
          tectonic-unwrapped = unfreePkgs.tectonic-unwrapped.overrideAttrs (old: {
            buildInputs = old.buildInputs ++ [ unfreePkgs.aws-lc ];
          });
        };
        alduin = pkgs.vimUtils.buildVimPlugin {
          name = "alduin";
          src = inputs.plugins-alduin;
        };
      };
    };
}
