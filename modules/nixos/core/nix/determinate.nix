{ inputs, ... }:
{
  flake.modules.nixos.nix = {
    imports = [ inputs.determinate.nixosModules.default ];

    nix.settings = {
      eval-cores = 0;
    };
  };
}
