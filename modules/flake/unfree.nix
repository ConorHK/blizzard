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
      modules =
        let
          predicate =
            pkg:
            builtins.elem (lib.getName pkg) config.nixpkgs.allowedUnfreePackages
            || builtins.any (
              prefix: lib.hasPrefix prefix (lib.getName pkg)
            ) config.nixpkgs.allowedUnfreePackagePrefixes;
        in
        {
          nixos.core.nixpkgs.config.allowUnfreePredicate = predicate;
        };

      unfree = config.nixpkgs.allowedUnfreePackages;
    };
  };
}
