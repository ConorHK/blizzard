{ inputs, ... }:
{
  flake.modules.nixos.determinate-nix = {
    imports = [ inputs.determinate.nixosModules.default ];

    nix.settings = {
      eval-cores = 0;
    };
  };
}
