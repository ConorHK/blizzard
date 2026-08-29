{ lib, config, ... }:
{
  options = {
    nixpkgs.allowedUnfreePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    nixpkgs.allowedUnfreePackagePrefixes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = {
    flake = {
      lib.allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages
        || builtins.any (
          prefix: lib.hasPrefix prefix (lib.getName pkg)
        ) config.nixpkgs.allowedUnfreePackagePrefixes;

      modules.nixos.core.nixpkgs.config.allowUnfreePredicate = config.flake.lib.allowUnfreePredicate;

      unfree = config.nixpkgs.allowedUnfreePackages;
    };
  };
}
