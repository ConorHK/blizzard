{ lib, config, ... }:
{
  options.nixpkgs.allowedInsecurePackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  # nixpkgs.config merges by recursiveUpdate, so lists clobber.
  config.flake.modules.nixos.core.nixpkgs.config.permittedInsecurePackages =
    config.nixpkgs.allowedInsecurePackages;
}
