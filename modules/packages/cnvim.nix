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
      self',
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
        herdr-nvim = self'.packages.herdr-nvim.vimPlugin;
        alduin = pkgs.vimUtils.buildVimPlugin {
          name = "alduin";
          src = inputs.plugins-alduin;
        };
        vscode-java-debug = pkgs.vscode-extensions.vscjava.vscode-java-debug;
        vscode-java-test = pkgs.vscode-extensions.vscjava.vscode-java-test;
      };
    };
}
