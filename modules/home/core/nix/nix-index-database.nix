{ inputs, ... }:
{
  flake.modules.homeManager.nix-index-database = {
    imports = [
      inputs.nix-index-database.homeModules.nix-index
    ];

    programs = {
      nix-index-database.comma.enable = true;
    };
  };
}
