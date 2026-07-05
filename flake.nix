{
  description = "blizzard - nix dot files";
  inputs = {
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix.inputs.darwin.follows = "";
    agenix.inputs.home-manager.follows = "home-manager";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    claude-code.url = "github:sadjow/claude-code-nix";
    cnvim.inputs.nixpkgs.follows = "nixpkgs";
    cnvim.url = "github:conorhk/vimrc";
    crash.inputs.nixpkgs.follows = "nixpkgs";
    crash.url = "github:RGBCube/crash";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    devenv-root.flake = false;
    devenv-root.url = "file+file:///dev/null";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    devenv.url = "github:cachix/devenv";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    import-tree.url = "github:vic/import-tree";
    lanzaboote.url = "github:nix-community/lanzaboote";
    # Not referenced by this repo, but devenv's flakeModule requires it to
    # evaluate its `containers` output during `nix flake check`.
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    nix-gaming.url = "github:fufexan/nix-gaming";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";
    stylix.inputs.flake-parts.follows = "flake-parts";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.url = "github:danth/stylix";
    textfox.inputs.nixpkgs.follows = "nixpkgs";
    textfox.url = "github:adriankarlen/textfox";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    wrappers.inputs.nixpkgs.follows = "nixpkgs";
    wrappers.url = "github:Lassulus/wrappers";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
