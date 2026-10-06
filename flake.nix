{
  description = "blizzard - nix dot files";
  inputs = {
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
    crash.inputs.nixpkgs.follows = "nixpkgs";
    crash.url = "github:RGBCube/crash";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    import-tree.url = "github:vic/import-tree";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
    lanzaboote.url = "github:nix-community/lanzaboote";
    neovim-nightly-overlay.inputs.nixpkgs.follows = "nixpkgs";
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
    nix-gaming.inputs.flake-parts.follows = "flake-parts";
    nix-gaming.inputs.nixpkgs.follows = "nixpkgs";
    nix-gaming.url = "github:fufexan/nix-gaming";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # No x86_64-darwin hosts.
    pi.inputs.nixpkgs-darwin-x64.follows = "nixpkgs";
    pi.inputs.nixpkgs.follows = "nixpkgs";
    pi.url = "github:earendil-works/pi/stable";
    plugins-alduin = {
      url = "github:conorhk/alduin.nvim";
      flake = false;
    };
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
